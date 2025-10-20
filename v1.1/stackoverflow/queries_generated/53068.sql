-- {"query": "53068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 942} 

WITH TopTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS Rank
    FROM Tags t
    WHERE t.Count > 1000
    LIMIT 10
),
UserPosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
      AND p.Tags IS NOT NULL
),
TaggedUserPosts AS (
    SELECT 
        up.PostId,
        up.UserId,
        up.PostTypeId,
        up.Score,
        up.CreationDate,
        tt.TagId
    FROM UserPosts up
    JOIN TopTags tt ON up.TagName = tt.TagName
),
UserAggregates AS (
    SELECT 
        tup.UserId,
        tup.TagId,
        COUNT(CASE WHEN tup.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN tup.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(tup.Score) AS AvgScore,
        SUM(tup.Score) AS TotalScore,
        MIN(tup.CreationDate) AS FirstPostDate,
        MAX(tup.CreationDate) AS LastPostDate
    FROM TaggedUserPosts tup
    GROUP BY tup.UserId, tup.TagId
),
UserBadges AS (
    SELECT 
        b.UserId,
        t.Id AS TagId,
        COUNT(*) AS GoldBadges
    FROM Badges b
    JOIN Tags t ON b.Name = t.TagName
    WHERE b.Class = 1 AND b.TagBased = TRUE
    GROUP BY b.UserId, t.Id
),
UserVotes AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    GROUP BY v.PostId
),
UserEdits AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)  -- Edits and Rollbacks
    GROUP BY ph.PostId
),
Combined AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        tt.TagName,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgScore,
        ua.TotalScore,
        ua.FirstPostDate,
        ua.LastPostDate,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        SUM(uv.UpVotes) AS TotalUpVotes,
        SUM(uv.DownVotes) AS TotalDownVotes,
        SUM(ue.EditCount) AS TotalEdits
    FROM Users u
    JOIN UserAggregates ua ON u.Id = ua.UserId
    JOIN TopTags tt ON ua.TagId = tt.TagId
    LEFT JOIN UserBadges ub ON u.Id = ub.UserId AND ua.TagId = ub.TagId
    JOIN TaggedUserPosts tup ON u.Id = tup.UserId AND ua.TagId = tup.TagId
    LEFT JOIN UserVotes uv ON tup.PostId = uv.PostId
    LEFT JOIN UserEdits ue ON tup.PostId = ue.PostId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation, tt.TagName, ua.QuestionCount, ua.AnswerCount, ua.AvgScore, ua.TotalScore, ua.FirstPostDate, ua.LastPostDate, ub.GoldBadges
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    TagName,
    QuestionCount,
    AnswerCount,
    AvgScore,
    TotalScore,
    FirstPostDate,
    LastPostDate,
    GoldBadges,
    TotalUpVotes,
    TotalDownVotes,
    TotalEdits,
    RANK() OVER (PARTITION BY TagName ORDER BY TotalScore DESC) AS RankInTag
FROM Combined
ORDER BY TagName, RankInTag;
