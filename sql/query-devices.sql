SELECT STU.ID,
 [DRA].[SCL] AS [School],
 [STU].[SEM] AS [StuEmail],
 [DRA].[CD] AS [Code],
 CONVERT(VARCHAR(10),[DRA].[DT],101) AS [Issued],
 CONVERT(VARCHAR(10),[DRA].[RD],101) AS [Returned],
 [DRA].[DD] as [Last Ticket Date],
 [DRI].[BC] AS Barcode
FROM (SELECT [STU].* FROM STU WHERE DEL = 0)
 STU RIGHT JOIN ((SELECT [DRA].* FROM DRA WHERE DEL = 0)
 DRA LEFT JOIN (SELECT [DRI].* FROM DRI WHERE DEL = 0)
 DRI ON [DRI].[RID] = [DRA].[RID] AND [DRI].[RIN] = [DRA].[RIN]) ON [STU].[ID] = [DRA].[ID]
WHERE
 DRA.CD IN ('M','S','V','R',NULL,'')
 AND
 DRA.RID = 1
 AND
 DRI.DEL <> 1
 AND
 ( [DRA].[DTS] > DATEADD(day,-3,getdate()) )
