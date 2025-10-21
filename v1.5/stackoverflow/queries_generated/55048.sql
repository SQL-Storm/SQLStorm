-- {"query": "55048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1244} 

WITH 
-- Base set of recent questions
RecentQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1                     -- Question
      AND p.CreationDate >= DATE '2022-01-01'
),

-- Latest edit (title, body or tags) for each question
LatestEdits AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS HasEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)      -- Edit Title/Body/Tags
    GROUP BY ph.PostId
),

-- Aggregate vote score per question (upvotes - downvotes)
VoteScores AS (
    SELECT 
        v.PostId,
        SUM(CASE 
                WHEN v.VoteTypeId = 2 THEN 1   -- UpMod
                WHEN v.VoteTypeId = 3 THEN -1  -- DownMod
                ELSE 0
            END) AS NetVoteScore
    FROM Votes v
    WHERE v.CreationDate >= DATE '2022-01-01'
    GROUP BY v.PostId
),

-- Badge counts per user (Gold, Silver, Bronze)
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),

-- Tag frequency for the selected period
TagFrequencies AS (
    SELECT 
        unnest(string_to_array(trim(both '<>' FROM t.Tags), '><')) AS Tag,
        COUNT(*) AS TagUseCount
    FROM RecentQuestions t
    GROUP BY Tag
),

-- Rank tags by frequency
TopTags AS (
    SELECT 
        Tag,
        TagUseCount,
        RANK() OVER (ORDER BY TagUseCount DESC) AS TagRank
    FROM TagFrequencies
    WHERE TagUseCount > 1000
),

-- Combine everything
QuestionMetrics AS (
    SELECT 
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.Tags,
        COALESCE(e.LastEditDate, q.CreationDate) AS LastActivityDate,
        COALESCE(v.NetVoteScore, 0) AS NetVoteScore,
        u.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS UserQuestionRank
    FROM RecentQuestions q
    LEFT JOIN LatestEdits e      ON e.PostId = q.Id
    LEFT JOIN VoteScores v       ON v.PostId = q.Id
    LEFT JOIN Users u            ON u.Id = q.OwnerUserId
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = q.OwnerUserId
)

SELECT 
    qm.Id,
    qm.Title,
    qm.CreationDate,
    qm.Score,
    qm.ViewCount,
    qm.AnswerCount,
    qm.FavoriteCount,
    qm.NetVoteScore,
    qm.Reputation,
    qm.GoldBadges,
    qm.SilverBadges,
    qm.BronzeBadges,
    qm.UserQuestionRank,
    tt.Tag,
    tt.TagUseCount,
    tt.TagRank
FROM QuestionMetrics qm
LEFT JOIN LATERAL (
    SELECT 
        tag,
        TagUseCount,
        TagRank
    FROM TopTags
    WHERE tag = ANY (SELECT unnest(string_to_array(trim(both '<>' FROM qm.Tags), '><')))
    ORDER BY TagRank
    LIMIT 3
) tt ON TRUE
ORDER BY qm.NetVoteScore DESC, qm.ViewCount DESC
LIMIT 500;
