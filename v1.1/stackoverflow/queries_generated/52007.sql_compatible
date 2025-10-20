SELECT 
    t.TagName,
    AVG(p.Score) AS AvgScore,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    SUM(p.ViewCount) AS TotalViews,
    COUNT(DISTINCT v.Id) AS TotalVotes
FROM 
    Tags t
JOIN 
    Posts q ON EXISTS (
        SELECT 1
        FROM UNNEST(string_to_array(substring(q.Tags FROM 2 FOR length(q.Tags)-2), '><')) AS tagname(tag)
        WHERE tagname.tag = t.TagName
    )
LEFT JOIN Posts p ON p.Id = q.Id
LEFT JOIN Votes v ON v.PostId = q.Id
WHERE 
    q.PostTypeId = 1
    AND q.CreationDate >= DATE '2015-01-01'
GROUP BY 
    t.Id, t.TagName
HAVING 
    COUNT(DISTINCT p.Id) > 100
ORDER BY 
    AvgScore DESC, TotalViews DESC
LIMIT 20;