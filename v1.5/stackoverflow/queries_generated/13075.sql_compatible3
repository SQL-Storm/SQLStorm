WITH UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) DESC) AS QuestionRank,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) DESC) AS AnswerRank
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.LastAccessDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 days'
    GROUP BY 
        u.Id, u.DisplayName
),
PostAnalysis AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        ph.CreationDate AS LastEditDate,
        LAG(ph.CreationDate) OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS PreviousEditDate,
        COUNT(DISTINCT c.Id) AS CommentCount,
        STRING_AGG(DISTINCT t.TagName, ', ') AS TagList
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 5
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE 
        p.PostTypeId = 1 AND
        p.CreationDate BETWEEN TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year' AND TIMESTAMP '2024-10-01 12:34:56'
    GROUP BY 
        p.Id, ph.CreationDate
)
SELECT
    ua.Id,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalScore,
    pa.Title,
    pa.LastEditDate,
    pa.PreviousEditDate,
    pa.CommentCount,
    pa.TagList,
    CASE 
        WHEN pa.LastEditDate IS NULL THEN 'Never Edited'
        WHEN EXTRACT(DAY FROM (pa.LastEditDate - pa.PreviousEditDate)) <= 7 THEN 'Edited Within a Week'
        ELSE 'Edited More Than a Week Ago'
    END AS EditStatus,
    (SELECT AVG(Reputation) FROM Users WHERE Reputation > 1000) AS AvgHighRep
FROM 
    UserActivity ua
JOIN 
    PostAnalysis pa ON ua.Id = pa.OwnerUserId
WHERE 
    ua.QuestionRank <= 10 OR ua.AnswerRank <= 10
GROUP BY
    ua.Id,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalScore,
    pa.Title,
    pa.LastEditDate,
    pa.PreviousEditDate,
    pa.CommentCount,
    pa.TagList,
    CASE 
        WHEN pa.LastEditDate IS NULL THEN 'Never Edited'
        WHEN EXTRACT(DAY FROM (pa.LastEditDate - pa.PreviousEditDate)) <= 7 THEN 'Edited Within a Week'
        ELSE 'Edited More Than a Week Ago'
    END
ORDER BY 
    ua.TotalScore DESC
LIMIT 10;