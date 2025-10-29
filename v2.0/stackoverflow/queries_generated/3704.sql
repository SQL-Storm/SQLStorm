-- {"query": "3704.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2186} 

WITH 
-- Explode tags for every question
TagQuestions AS (
    SELECT 
        p.Id               AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        UNNEST(
            STRING_TO_ARRAY(
                SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), 
                '><'
            )
        )                  AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1                -- only questions
),

-- Aggregate per‑tag statistics
TagStats AS (
    SELECT 
        tq.Tag,
        COUNT(*)                               AS QuestionCount,
        AVG(tq.Score)                          AS AvgQuestionScore,
        MAX(tq.ViewCount)                      AS MaxViews,
        SUM(CASE WHEN tq.Score IS NULL THEN 1 ELSE 0 END) AS NullScoreCount
    FROM TagQuestions tq
    GROUP BY tq.Tag
),

-- Keep only the most popular tags
TopTags AS (
    SELECT 
        ts.Tag,
        ts.QuestionCount,
        ts.AvgQuestionScore,
        ts.MaxViews,
        ROW_NUMBER() OVER (ORDER BY ts.QuestionCount DESC) AS TagRank
    FROM TagStats ts
    WHERE ts.QuestionCount > 100
),

-- Answers per user per tag
UserAnswers AS (
    SELECT 
        a.OwnerUserId                     AS UserId,
        tq.Tag,
        COUNT(*)                          AS AnswerCount,
        AVG(a.Score)                      AS AvgAnswerScore,
        MAX(a.CreationDate)               AS LastAnswerDate
    FROM Posts a
    JOIN TagQuestions tq ON tq.QuestionId = a.ParentId
    WHERE a.PostTypeId = 2                -- only answers
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId, tq.Tag
),

-- Rank users inside each tag
UserRankings AS (
    SELECT 
        ua.UserId,
        ua.Tag,
        ua.AnswerCount,
        ua.AvgAnswerScore,
        ROW_NUMBER() OVER (
            PARTITION BY ua.Tag 
            ORDER BY ua.AnswerCount DESC, ua.AvgAnswerScore DESC
        )                                 AS RankInTag
    FROM UserAnswers ua
),

-- Badge summary per user
UserBadgeInfo AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),

-- User reputation plus badge info
UserReputation AS (
    SELECT 
        u.Id            AS UserId,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        u.Reputation,
        COALESCE(ubi.GoldBadges,   0)   AS GoldBadges,
        COALESCE(ubi.SilverBadges, 0)   AS SilverBadges,
        COALESCE(ubi.BronzeBadges, 0)   AS BronzeBadges
    FROM Users u
    LEFT JOIN UserBadgeInfo ubi ON ubi.UserId = u.Id
),

-- Total votes per user (correlated sub‑query)
UserVoteTotals AS (
    SELECT 
        u.Id AS UserId,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = u.Id 
           AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = u.Id 
           AND v.VoteTypeId = 3) AS DownVoteCount
    FROM Users u
),

-- Assemble the final result set for tags that have active contributors
ActiveTagContributors AS (
    SELECT 
        tt.Tag,
        tt.QuestionCount,
        tt.AvgQuestionScore,
        tt.MaxViews,
        ur.UserId,
        ur.DisplayName,
        ur.Reputation,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        uv.UpVoteCount,
        uv.DownVoteCount,
        urk.AnswerCount,
        urk.AvgAnswerScore,
        urk.RankInTag
    FROM TopTags tt
    LEFT JOIN UserRankings urk 
           ON urk.Tag = tt.Tag 
          AND urk.RankInTag <= 3                     -- top‑3 users per tag
    LEFT JOIN UserReputation ur 
           ON ur.UserId = urk.UserId
    LEFT JOIN UserVoteTotals uv 
           ON uv.UserId = urk.UserId
    WHERE tt.TagRank <= 10
),

-- Tags that have questions but no recorded answers (NULL‑logic example)
TagWithoutAnswers AS (
    SELECT 
        ts.Tag,
        ts.QuestionCount,
        ts.AvgQuestionScore,
        ts.MaxViews,
        NULL AS UserId,
        NULL AS DisplayName,
        NULL AS Reputation,
        NULL AS GoldBadges,
        NULL AS SilverBadges,
        NULL AS BronzeBadges,
        0    AS UpVoteCount,
        0    AS DownVoteCount,
        0    AS AnswerCount,
        NULL AS AvgAnswerScore,
        NULL AS RankInTag
    FROM TagStats ts
    WHERE NOT EXISTS (
        SELECT 1 
        FROM TagQuestions tq
        JOIN Posts a ON a.ParentId = tq.QuestionId 
                     AND a.PostTypeId = 2
        WHERE tq.Tag = ts.Tag
    )
)

-- Union the two result sets and order for consumption
SELECT *
FROM ActiveTagContributors
UNION ALL
SELECT *
FROM TagWithoutAnswers
ORDER BY Tag, RankInTag NULLS LAST;
