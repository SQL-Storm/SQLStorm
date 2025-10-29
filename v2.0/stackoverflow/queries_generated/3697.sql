-- {"query": "3697.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1901} 

/*  Benchmark query: heavy use of CTEs, window functions, outer joins,
    correlated sub‑queries, set operators, string ops and NULL logic   */
WITH 
-- 1. Top 100 users by reputation with their badge summary
TopUsers AS (
    SELECT 
        u.Id                     AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id)              AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ',')          AS BadgeNames
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    ORDER BY u.Reputation DESC
    FETCH FIRST 100 ROWS ONLY
),

-- 2. Recent activity per post (last comment, last vote, last edit)
PostActivity AS (
    SELECT 
        p.Id                               AS PostId,
        p.Title,
        p.PostTypeId,
        COALESCE(p.Tags, '')               AS Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        /* last comment (outer apply) */
        (SELECT c.Text
         FROM Comments c
         WHERE c.PostId = p.Id
         ORDER BY c.CreationDate DESC
         FETCH FIRST 1 ROW ONLY)           AS LastCommentText,
        /* last vote type */
        (SELECT vt.Name
         FROM Votes v
         JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
         WHERE v.PostId = p.Id
         ORDER BY v.CreationDate DESC
         FETCH FIRST 1 ROW ONLY)           AS LastVoteType,
        /* last editor (if any) */
        (SELECT COALESCE(u.DisplayName, p.LastEditorDisplayName)
         FROM Users u
         WHERE u.Id = p.LastEditorUserId)  AS LastEditorName,
        /* days since last activity */
        EXTRACT(DAY FROM (CURRENT_TIMESTAMP - GREATEST(
            p.LastActivityDate,
            COALESCE((SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id), p.CreationDate),
            COALESCE((SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id), p.CreationDate)
        )))                                 AS DaysSinceLastActivity
    FROM Posts p
    WHERE p.PostTypeId = 1               -- only questions
),

-- 3. Tag‑level aggregates (including string parsing of the Tags column)
TagStats AS (
    SELECT 
        TRIM(BOTH '><' FROM UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) ) AS Tag,
        COUNT(*)                        AS QuestionCount,
        AVG(p.Score)                    AS AvgScore,
        AVG(p.ViewCount)                AS AvgViews,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAccepted,
        SUM(p.FavoriteCount)            AS TotalFavorites,
        MAX(p.CreationDate)             AS MostRecentQuestion
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY Tag
),

-- 4. Correlated sub‑query: best answer per question (by score, with tie‑breaker on creation date)
BestAnswers AS (
    SELECT 
        q.Id                                   AS QuestionId,
        (SELECT a.Id
         FROM Posts a
         WHERE a.ParentId = q.Id
           AND a.PostTypeId = 2
         ORDER BY a.Score DESC, a.CreationDate ASC
         FETCH FIRST 1 ROW ONLY)               AS BestAnswerId,
        (SELECT a.Score
         FROM Posts a
         WHERE a.Id = (SELECT a2.Id
                       FROM Posts a2
                       WHERE a2.ParentId = q.Id
                         AND a2.PostTypeId = 2
                       ORDER BY a2.Score DESC, a2.CreationDate ASC
                       FETCH FIRST 1 ROW ONLY)
         )                                      AS BestAnswerScore
    FROM Posts q
    WHERE q.PostTypeId = 1
),

-- 5. Union of two activity streams: recent posts vs recent badge awards
RecentActivityUnion AS (
    SELECT 
        p.CreationDate   AS EventDate,
        'Post'            AS EventType,
        p.Title           AS Description,
        p.Id              AS RefId,
        NULL              AS ExtraInfo
    FROM Posts p
    WHERE p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days'

    UNION ALL

    SELECT 
        b.Date           AS EventDate,
        'Badge'          AS EventType,
        b.Name           AS Description,
        b.UserId         AS RefId,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            WHEN b.Class = 3 THEN 'Bronze'
            ELSE 'Other' 
        END               AS ExtraInfo
    FROM Badges b
    WHERE b.Date > CURRENT_TIMESTAMP - INTERVAL '30 days'
),

-- 6. Outer join between posts and their history entries (latest edit only)
PostLatestHistory AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment AS HistoryComment,
        ph.Text    AS HistoryText,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)               -- edits to title, body, tags
)

SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalBadges,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.BadgeNames,
    pa.PostId,
    pa.Title,
    pa.Score,
    pa.ViewCount,
    pa.AnswerCount,
    pa.FavoriteCount,
    pa.LastCommentText,
    pa.LastVoteType,
    pa.LastEditorName,
    pa.DaysSinceLastActivity,
    ba.BestAnswerId,
    ba.BestAnswerScore,
    ts.Tag,
    ts.QuestionCount,
    ts.AvgScore,
    ts.AvgViews,
    ts.QuestionsWithAccepted,
    ts.TotalFavorites,
    ts.MostRecentQuestion,
    rh.HistoryComment,
    rh.HistoryText,
    ra.EventDate,
    ra.EventType,
    ra.Description,
    ra.ExtraInfo
FROM TopUsers tu
LEFT JOIN Posts p ON p.OwnerUserId = tu.UserId AND p.PostTypeId = 1
LEFT JOIN PostActivity pa ON pa.PostId = p.Id
LEFT JOIN BestAnswers ba ON ba.QuestionId = p.Id
LEFT JOIN LATERAL (
    SELECT *
    FROM TagStats ts
    WHERE ts.Tag = ANY (SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')))
    LIMIT 1
) ts ON TRUE
LEFT JOIN PostLatestHistory rh ON rh.PostId = p.Id AND rh.rn = 1
LEFT JOIN LATERAL (
    SELECT *
    FROM RecentActivityUnion ra
    WHERE ra.RefId = COALESCE(p.Id, tu.UserId)
      AND ra.EventDate > CURRENT_TIMESTAMP - INTERVAL '7 days'
    ORDER BY ra.EventDate DESC
    FETCH FIRST 1 ROW ONLY
) ra ON TRUE
WHERE tu.Reputation > 1000
ORDER BY tu.Reputation DESC, pa.DaysSinceLastActivity ASC
LIMIT 200;
