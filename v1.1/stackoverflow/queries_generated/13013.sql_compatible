WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) DESC) AS EditRank,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViews,
        MAX(b.Date) AS LastBadgeDate
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.UserId = u.Id
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000
        AND ph.CreationDate BETWEEN DATE_TRUNC('month', CAST('2024-10-01' AS date)) - INTERVAL '1 year' AND CAST('2024-10-01' AS date)
    GROUP BY 
        u.Id, u.DisplayName
),
RecentComments AS (
    SELECT
        p.Id AS PostId,
        COUNT(c.Id) AS CommentCount,
        /* To satisfy SQL dialects that require ORDER BY expressions to appear in the aggregate's argument list when using DISTINCT,
           aggregate the texts without DISTINCT and then deduplicate via array_agg + ordering where supported; for portability,
           use STRING_AGG over a subquery that selects distinct texts per post ordered by CreationDate. */
        (SELECT STRING_AGG(t.Text, ' | ')
         FROM (
             SELECT DISTINCT c2.Text, c2.CreationDate
             FROM Comments c2
             WHERE c2.PostId = p.Id
               AND c2.CreationDate >= DATE_TRUNC('month', CAST('2024-10-01' AS date)) - INTERVAL '3 months'
             ORDER BY c2.CreationDate DESC
         ) t
        ) AS RecentComments
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId AND c.CreationDate >= DATE_TRUNC('month', CAST('2024-10-01' AS date)) - INTERVAL '3 months'
    GROUP BY 
        p.Id
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.EditCount,
    ua.AvgQuestionViews,
    rc.CommentCount,
    SUBSTRING(rc.RecentComments FROM 1 FOR 200) AS TruncatedRecentComments,
    COALESCE(b.Name, 'No Badge') AS LastBadgeEarned
FROM 
    UserActivity ua
LEFT JOIN 
    RecentComments rc ON ua.UserId = rc.PostId
LEFT JOIN 
    Badges b ON ua.UserId = b.UserId AND b.Date = ua.LastBadgeDate
WHERE 
    ua.EditRank <= 100
ORDER BY 
    ua.EditCount DESC, ua.QuestionCount DESC;