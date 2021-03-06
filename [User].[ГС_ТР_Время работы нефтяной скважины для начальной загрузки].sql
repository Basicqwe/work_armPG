USE [kgsu]
GO
/****** Object:  UserDefinedFunction [User].[ГС_ТР_Время работы нефтяной скважины для начальной загрузки]    Script Date: 08/21/2015 09:05:33 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER FUNCTION [User].[ГС_ТР_Время работы нефтяной скважины для начальной загрузки]
(
  @@ID_Скважины                UNIQUEIDENTIFIER,
  @@ID_Шахматки                UNIQUEIDENTIFIER,
  @@ID_плана                   UNIQUEIDENTIFIER,
  @@Дата_шахматки              SMALLDATETIME
)
RETURNS FLOAT
AS
BEGIN
  DECLARE
    @Текущая_дата               SMALLDATETIME,
    @Result                     FLOAT,
    @last_result                FLOAT,
    @last_res_остаток           FLOAT,
    @last_result_date           SMALLDATETIME,
    @last_edit_date             SMALLDATETIME,
    @Последний_запуск           SMALLDATETIME,
    @Последний_заполненный_день SMALLDATETIME,
    @ID_Плана                   UNIQUEIDENTIFIER,
    @ID_Типа_плана              UNIQUEIDENTIFIER,
    @ID                         UNIQUEIDENTIFIER,
    @АПВ                        VARCHAR(50),    
    @Количество_остановок       INT,
    @Коэффициент_АПВ            FLOAT,
    @Календарное_время_факт     FLOAT,
    @Календарное_время_прогноз  FLOAT,
    @Дата_предыдущего_техрежима SMALLDATETIME
  
  DECLARE @Остановки TABLE
  (
    [Значение]    FLOAT,
    [Дата]        SMALLDATETIME,
    [Дата записи] SMALLDATETIME
  )    
       
  SET @Текущая_Дата = GETDATE()
  
  SELECT @ID_Типа_плана = [ID_Типа_плана] FROM [Plan].[_Планы] WHERE [ID_Плана] = @@ID_Плана
  
  SELECT @ID = [Plan].[Пл_Действующий план на дату](@ID_Типа_плана, @@Дата_шахматки) 
  
  SELECT 
    TOP 1 @АПВ = ПТ.[Текстовое значение] 
  FROM 
    [Plan].[_Показатели техрежима] ПТ
    JOIN
    Class.[Отношения объектов] ОО
      ON  ПТ.[ID_Пласта_скважины] = ОО.[ID_Второго_объекта]
  WHERE 
    ОО.[ID_Первого_объекта] = @@ID_Скважины AND
    ПТ.[ID_Типа_показателя_техрежима] = '8632a7ac-4505-44a5-a811-953dc95000bb' AND
    ПТ.[ID_Плана_техрежима] = @ID
  
  INSERT INTO @Остановки
  (
    [Значение],
    [Дата],
    [Дата записи]
  )
  SELECT
    ФЗПШ.[Значение],
    ФЗПШ.[Дата значения],
    ФЗПШ.[Дата изменения]
  FROM
    [Class].[Фактические значения параметров скважин в шахматке] ФЗПШ
    JOIN
    [Class].[Параметры скважин в шахматке] ПСШ 
      ON ПСШ.[ID_Параметра_скважины_в_шахматке] = ФЗПШ.[ID_Параметра_скважины_в_шахматке]
    JOIN
    Class.[Типы параметров для типов шахматки] ТПТШ 
      ON ТПТШ.[ID_Типа_параметра_для_типов_шахматки] = ПСШ.[ID_Типа_параметра_для_типов_шахматки]
  WHERE
    ПСШ.[ID_Шахматки] = @@ID_Шахматки AND
    ПСШ.[ID_Скважины] = @@ID_Скважины AND
    ТПТШ.[Тип шахматки] = 'Нефтяная' AND
    ТПТШ.[ID_Типа_параметра_скважины_в_шахматке] = '9249a58b-a9fa-447f-b182-d83c7853fe11' AND
    ФЗПШ.[Значение] IS NOT NULL AND
    MONTH(ФЗПШ.[Дата значения]) = MONTH(@@Дата_шахматки) AND
    YEAR(ФЗПШ.[Дата значения]) = YEAR(@@Дата_шахматки)
  
  SELECT
    @Result = SUM([Значение])/60.0
  FROM
   @Остановки
  
  SELECT
    TOP 1 @last_result = [Значение]
  FROM
    @Остановки
  WHERE [Дата] = [User].[Сервис_Дата без времени](@Текущая_Дата)
  ORDER BY [Дата] DESC
  
  SELECT
    TOP 1 @last_result_date = [Дата]
  FROM
    @Остановки
  WHERE [Дата] = [User].[Сервис_Дата без времени](@Текущая_Дата)
  ORDER BY [Дата] DESC
  
  SELECT
    TOP 1 @last_edit_date = [Дата записи]
  FROM
    @Остановки
  ORDER BY [Дата] DESC
  
  SET @last_res_остаток = (1440 - @last_result)/60.0
   
  IF MONTH(@Текущая_Дата) = MONTH(@@Дата_шахматки)
  BEGIN
        
    SET @Календарное_время_факт = 
      DATEDIFF(
        minute, 
        [User].[Сервис_Дата начала месяца](@@Дата_шахматки), 
        @last_result_date
      )/60.0 + DATEDIFF(minute, @last_result_date, @last_edit_date)/60.0
    
    SET @Календарное_время_прогноз = 
      DATEDIFF(
        minute, 
        [User].[Сервис_Дата начала месяца](@@Дата_шахматки), 
        DATEADD(day, 1, [User].[Сервис_Дата конца месяца](@@Дата_шахматки))
      )/60.0 - @Календарное_время_факт    
    
    -- ищем дату запуска последней остановки и были ли остановки на скважине
    -- если дата шахматки меньше 01.08.2015, то ищем остановки по старым структурам
    IF @@Дата_шахматки < '01.08.2015'
    BEGIN
      SELECT 
      TOP 1 @Последний_запуск = [ООС].[Время запуска скважины] 
      FROM 
        Class.[_Оперативные остановки скважин]  [ООС]
        JOIN
        Class.[Отношения объектов] [ОО]
          ON [ООС].[ID_Оперативной_остановки_скважины] = [ОО].[ID_Второго_объекта]
      WHERE
        [ОО].[ID_Первого_объекта] = @@ID_Скважины
      ORDER BY 
        CONVERT(DATETIME, [ООС].[Название оперативной остановки скважины], 126) DESC
        
      SELECT TOP 1
        @Количество_остановок = 1 --COUNT([ООС].[Время запуска скважины]) 
      FROM 
        Class.[_Оперативные остановки скважин]  [ООС]
        JOIN
        Class.[Отношения объектов] [ОО]
          ON [ООС].[ID_Оперативной_остановки_скважины] = [ОО].[ID_Второго_объекта]
      WHERE
        [ОО].[ID_Первого_объекта] = @@ID_Скважины
    END
    ELSE
    BEGIN
      -- после 01.08.2015 ищем остановки в ЖСС
      SELECT
        TOP 1 @Последний_запуск = [ОС].[Дата окончания] 
      FROM
        [Cache].[Остановки скважин] AS ОС
      WHERE
        [ID_Скважины] = @@ID_Скважины
      ORDER BY [ОС].[Дата начала] DESC
      
      SELECT TOP 1
        @Количество_остановок = 1 --COUNT([ОС].[Дата окончания остановки])
      FROM
        [Cache].[Остановки скважин] AS ОС
      WHERE
        [ID_Скважины] = @@ID_Скважины
    END

  
    SELECT
      TOP 1 @Последний_заполненный_день = [Дата]
    FROM
      @Остановки
    ORDER BY
      [Дата] DESC
    
    SET @Коэффициент_АПВ = 
      CASE 
        WHEN @АПВ IS NOT NULL THEN @Result/@Календарное_время_факт
        ELSE 1
      END
      
    IF @АПВ IS NULL
    BEGIN
      
      IF NOT (@Количество_остановок >= 1 AND @Последний_запуск IS NULL)
        SET @Result = @Result + @last_res_остаток + DATEDIFF(minute, @last_result_date, [User].[Сервис_Дата конца месяца](@@Дата_шахматки))/60.0
      /*IF @Количество_остановок >= 1
      BEGIN
        SET @Result = 
          CASE 
            WHEN @Последний_запуск IS NULL THEN @Result
            WHEN @Последний_запуск IS NOT NULL THEN @Result + @last_res_остаток + DATEDIFF(minute, @last_result_date, [User].[Сервис_Дата конца месяца](@@Дата_шахматки))/60.0
          END
      END
      ELSE
        SET @Result = @Result + @last_res_остаток + DATEDIFF(minute, @last_result_date, [User].[Сервис_Дата конца месяца](@@Дата_шахматки))/60.0*/
      
    END      
    ELSE
      SET @Result = @Result + @Коэффициент_АПВ * @Календарное_время_прогноз     
       
  END
  
  SET @Result = [User].[Сервис_Дней в месяце](@@Дата_шахматки) * 24.0 - @last_res_остаток - @Result
      
  RETURN @Result
END


