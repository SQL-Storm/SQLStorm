-- {"query": "3437.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2283} 

WITH
-- Recent questions (last 30 days) with parsed tag array
RecentQuestions AS (
    SELECT
        p.Id                               AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        regexp_split_to_array(trim(both '<>' FROM p.Tags), '><') AS TagArray,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= now() - INTERVAL '30 days'
),

-- Popularity metrics per tag among those recent questions
TagPopularity AS (
    SELECT
        UNNEST(q.TagArray)                AS Tag,
        COUNT(*)                          AS QCount,
        SUM(q.Score)                      AS TotalScore,
        SUM(q.ViewCount)                  AS TotalViews
    FROM RecentQuestions q
    GROUP BY 1
),

-- Per‑user aggregates (questions, votes, badges, bounty started)
UserStats AS (
    SELECT
        u.Id                                    AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT rq.QuestionId)           AS RecentQuestionCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount END),0) AS TotalBountyStarted,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0)       AS UpVotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0)       AS DownVotesGiven,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)                             AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)                             AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)                             AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)                    AS RepRank
    FROM Users u
    LEFT JOIN RecentQuestions rq ON rq.OwnerUserId = u.Id
    LEFT JOIN Votes v           ON v.UserId = u.Id
    LEFT JOIN Badges b          ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

-- Most recent close reason (if any) for each recent question
RecentClosedReasons AS (
    SELECT
        q.QuestionId,
        (
            SELECT ph.Comment
            FROM PostHistory ph
            WHERE ph.PostId = q.QuestionId
              AND ph.PostHistoryTypeId = 10               -- Post Closed
            ORDER BY ph.CreationDate DESC
            LIMIT 1
        ) AS CloseReasonCode
    FROM RecentQuestions q
    WHERE EXISTS (
        SELECT 1 FROM PostHistory ph
        WHERE ph.PostId = q.QuestionId
          AND ph.PostHistoryTypeId = 10
    )
),

-- Tag sets for set‑operator testing (popular vs rare)
TagSets AS (
    SELECT Tag, QCount, TotalScore, TotalViews, 'Popular' AS Category
    FROM TagPopularity
    WHERE QCount >= 100
    UNION ALL
    SELECT Tag, QCount, TotalScore, TotalViews, 'Rare' AS Category
    FROM TagPopularity
    WHERE QCount < 10
)

SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.RecentQuestionCount,
    us.TotalBountyStarted,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.RepRank,
    rq.Title,
    rq.Score                           AS QuestionScore,
    rq.ViewCount,
    rq.AnswerCount,
    COALESCE(rc.CloseReasonCode, '0')  AS CloseReason,
    ARRAY_TO_STRING(rq.TagArray, ', ') AS Tags,
    COALESCE(rq.FavoriteCount,0)       AS FavoriteCount,
    -- Custom engagement metric
    (rq.Score * 2 + rq.ViewCount/100 + rq.AnswerCount*5 + us.GoldBadges*10) AS EngagementScore,
    -- Rank questions per user by engagement
    ROW_NUMBER() OVER (PARTITION BY us.UserId
                       ORDER BY (rq.Score * 2 + rq.ViewCount/100 + rq.AnswerCount*5) DESC) AS QuestionRank,
    ts.Category
FROM UserStats us
LEFT JOIN RecentQuestions rq          ON rq.OwnerUserId = us.UserId
LEFT JOIN RecentClosedReasons rc     ON rc.QuestionId = rq.QuestionId
LEFT JOIN LATERAL (
    SELECT Tag, Category
    FROM TagSets ts
    WHERE ts.Tag = ANY(rq.TagArray)
    ORDER BY CASE WHEN ts.Category = 'Popular' THEN 1 ELSE 2 END
    LIMIT 1
) ts ON TRUE
WHERE us.RepRank <= 500
  AND (rq.Score IS NOT NULL OR rq.ViewCount IS NOT NULL)
ORDER BY us.Reputation DESC, EngagementScore DESC;
