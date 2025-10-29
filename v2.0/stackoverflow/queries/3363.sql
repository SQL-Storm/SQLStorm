WITH TagStats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id)                                        AS QuestionCount,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END)       AS PositiveScoreCount,
        AVG(p.Score)                                       AS AvgScore,
        MAX(p.ViewCount)                                   AS MaxViews,
        MIN(p.CreationDate)                                AS FirstAsked,
        MAX(p.CreationDate)                                AS LastAsked
    FROM Tags t
    JOIN Posts p 
         ON p.PostTypeId = 1
        AND p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    GROUP BY t.TagName
),
UserActivity AS (
    SELECT 
        u.Id                                             AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)      AS QuestionsAsked,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)      AS AnswersGiven,
        COALESCE(SUM(p.Score),0)                         AS TotalPostScore,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotesGiven,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score),0) DESC) AS ScoreRank
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v   ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
RecentClosed AS (
    SELECT 
        ph.PostId,
        MIN(ph.CreationDate)                               AS ClosedDate,
        MAX(CASE WHEN ph.Comment IS NOT NULL THEN ph.Comment END) AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10          -- Post Closed
    GROUP BY ph.PostId
),
GoldBadges AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)      AS GoldBadgeCount
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    ts.TagName,
    ts.QuestionCount,
    ts.PositiveScoreCount,
    ts.AvgScore,
    ts.MaxViews,
    ts.FirstAsked,
    ts.LastAsked,
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.TotalPostScore,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ua.ScoreRank,
    rc.ClosedDate,
    CASE 
        WHEN rc.CloseReasonId IS NULL THEN 'Unknown'
        ELSE COALESCE(crt.Name, 'Other')
    END                                            AS CloseReason,
    COALESCE(gb.GoldBadgeCount,0)                  AS GoldBadgeCount
FROM TagStats ts
LEFT JOIN LATERAL (
    SELECT p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%' || '<' || ts.TagName || '>' || '%'
    ORDER BY p.Score DESC
    LIMIT 1
) top_owner ON TRUE
LEFT JOIN UserActivity ua 
       ON ua.UserId = top_owner.OwnerUserId
LEFT JOIN LATERAL (
    SELECT p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags LIKE '%' || '<' || ts.TagName || '>' || '%'
    ORDER BY p.CreationDate DESC
    LIMIT 1
) latest_post ON TRUE
LEFT JOIN RecentClosed rc 
       ON rc.PostId = latest_post.Id
LEFT JOIN CloseReasonTypes crt 
       ON crt.Id = CAST(rc.CloseReasonId AS INTEGER)
LEFT JOIN GoldBadges gb 
       ON gb.UserId = ua.UserId
WHERE ts.QuestionCount > 5

UNION ALL

SELECT 
    'TOTAL'                                     AS TagName,
    SUM(ts.QuestionCount)                       AS QuestionCount,
    SUM(ts.PositiveScoreCount)                  AS PositiveScoreCount,
    AVG(ts.AvgScore)                            AS AvgScore,
    MAX(ts.MaxViews)                            AS MaxViews,
    MIN(ts.FirstAsked)                          AS FirstAsked,
    MAX(ts.LastAsked)                           AS LastAsked,
    NULL                                        AS DisplayName,
    NULL                                        AS QuestionsAsked,
    NULL                                        AS AnswersGiven,
    NULL                                        AS TotalPostScore,
    NULL                                        AS UpVotesGiven,
    NULL                                        AS DownVotesGiven,
    NULL                                        AS ScoreRank,
    NULL                                        AS ClosedDate,
    NULL                                        AS CloseReason,
    NULL                                        AS GoldBadgeCount
FROM TagStats ts
GROUP BY ()  -- ensure single aggregated row
ORDER BY QuestionCount DESC
LIMIT 100;