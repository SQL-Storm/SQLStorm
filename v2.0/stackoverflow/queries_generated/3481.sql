-- {"query": "3481.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2340} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.AboutMe, '') AS AboutMe,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven
    FROM Users u
    LEFT JOIN Badges b       ON b.UserId = u.Id
    LEFT JOIN Posts p        ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v        ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.AboutMe
),

QuestionMetrics AS (
    SELECT 
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        q.FavoriteCount,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        COALESCE(q.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS CommentCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3) AS DuplicateCount,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS RecentRank
    FROM Posts q
    WHERE q.PostTypeId = 1
),

TagExplode AS (
    SELECT 
        qm.Id AS PostId,
        TRIM(BOTH '<>' FROM UNNEST(string_to_array(qm.Tags, '><'))) AS Tag
    FROM QuestionMetrics qm
    WHERE qm.Tags IS NOT NULL
),

TagStats AS (
    SELECT 
        t.TagName AS Tag,
        COUNT(*) AS TagUseCount,
        SUM(qm.Score) AS TotalTagScore,
        ROUND(AVG(qm.ViewCount)::numeric, 2) AS AvgTagViews
    FROM TagExplode te
    JOIN QuestionMetrics qm ON qm.Id = te.PostId
    JOIN Tags t ON t.TagName = te.Tag
    GROUP BY t.TagName
),

RecentBadges AS (
    SELECT 
        b.UserId,
        STRING_AGG(b.Name, ', ') FILTER (WHERE b.Date >= CURRENT_DATE - INTERVAL '30 days') AS RecentBadgeList
    FROM Badges b
    GROUP BY b.UserId
)

SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.TotalQuestionViews,
    us.AnswerCount,
    us.UpVotesGiven,
    us.DownVotesGiven,
    rb.RecentBadgeList,
    qm.Title                     AS LatestQuestionTitle,
    qm.CreationDate              AS LatestQuestionDate,
    qm.Score                     AS LatestQuestionScore,
    qm.FavoriteCount             AS LatestQuestionFavorites,
    qm.ViewCount                 AS LatestQuestionViews,
    qm.CommentCount,
    qm.DuplicateCount,
    CASE 
        WHEN qm.AcceptedAnswerId <> 0 THEN 'Accepted' 
        ELSE 'Unaccepted' 
    END                         AS AcceptanceStatus,
    COALESCE(ts.TagUseCount,0)   AS TopTagUseCount,
    COALESCE(ts.TotalTagScore,0) AS TopTagScore,
    ts.AvgTagViews
FROM UserStats us
LEFT JOIN RecentBadges rb               ON rb.UserId = us.Id
LEFT JOIN LATERAL (
    SELECT *
    FROM QuestionMetrics qm
    WHERE qm.OwnerUserId = us.Id
    ORDER BY qm.CreationDate DESC
    LIMIT 1
) qm ON TRUE
LEFT JOIN LATERAL (
    SELECT *
    FROM TagStats ts
    WHERE ts.Tag = (
        SELECT te.Tag
        FROM TagExplode te
        WHERE te.PostId = qm.Id
        ORDER BY ts.TagUseCount DESC NULLS LAST
        LIMIT 1
    )
) ts ON TRUE
WHERE us.Reputation > 10000
  AND us.GoldBadges > 0
  AND (us.TotalQuestionViews + us.AnswerCount) > 500
  AND (us.UpVotesGiven - us.DownVotesGiven) > 100
ORDER BY us.Reputation DESC, us.GoldBadges DESC
LIMIT 100

UNION ALL

SELECT 
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE Reputation > 10000);
