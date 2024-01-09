SELECT
 [STU].[id],
 [DRA].[SCL] AS [school],
 [STU].[SEM] AS [gmail],
 [DRA].[CD] AS [code],
 CONVERT(VARCHAR(10),[DRA].[DT],101) AS [issued],
 CONVERT(VARCHAR(10),[DRA].[RD],101) AS [returned],
 [DRA].[DD] as [Last Ticket Date],
 [DRI].[BC] AS [barcode],
 [DRI].RIN,
 [DRA].[DTS]

FROM (SELECT [STU].* FROM STU WHERE DEL = 0)
 STU RIGHT JOIN ((SELECT [DRA].* FROM DRA WHERE DEL = 0)
 DRA LEFT JOIN (SELECT [DRI].* FROM DRI WHERE DEL = 0)
 DRI ON [DRI].[RID] = [DRA].[RID] AND [DRI].[RIN] = [DRA].[RIN]) ON [STU].[ID] = [DRA].[ID]
WHERE
 DRA.CD IN ('M','S','V')
 AND
 DRA.RID = 1
 AND
 DRI.DEL <> 1
 AND
 DRA.DD IS NULL
 AND
 ( [DRA].[DTS] > DATEADD(minute,-10,getdate()) )
 -- ( [DRA].[DTS] > DATEADD(day,-5,getdate()) )