-- {"query": "1079.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3350}
WITH UserPostAggregates AS (
    SELECT
        u.Id AS UserId,
        COALESCE(u.DisplayName, 'Anonymous User') AS DisplayName,
        u.CreationDate AS UserCreationDate,
        u.Reputation,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COALESCE(u.Location, 'Unknown Location') AS UserLocation,
        COUNT(DISTINCT p.Id) AS TotalPostsCount,
        SUM(p.Score) AS TotalPostsScore,
        AVG(p.Score) AS AveragePostScore,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostCreationDate,
        MIN(p.CreationDate) AS FirstPostCreationDate,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.DisplayName, u.CreationDate, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.Location
),
PostHistoryDetails AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        ph.Comment AS HistoryComment,
        ph.Text AS HistoryText,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_latest_history,
        LAG(ph.PostHistoryTypeId, 1, 0) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryType,
        CASE
            WHEN ph.PostHistoryTypeId = 10 AND (ph.Comment = '1' OR ph.Comment = '101') THEN TRUE
            ELSE FALSE
        END AS IsClosedAsDuplicate,
        CASE
            WHEN ph.PostHistoryTypeId = 35 THEN TRUE
            ELSE FALSE
        END AS IsMigratedAway
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 35)
),
TagPerformanceByUser AS (
    -- expand tag strings like '<tag1><tag2>' into rows using standard SQL methods
    SELECT
        p.OwnerUserId AS UserId,
        tag AS TagName,
        SUM(p.Score) AS TagScoreSum,
        COUNT(p.Id) AS TagPostCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY SUM(p.Score) DESC, COUNT(p.Id) DESC) AS rn_top_tag
    FROM Posts p
    CROSS JOIN LATERAL (
        -- split tags by '><' after removing leading '<' and trailing '>'
        SELECT TRIM(t) AS tag
        FROM (
            SELECT REGEXP_SPLIT_TO_TABLE(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><') AS t
        ) s
    ) split_tags
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, tag
    HAVING SUM(p.Score) > 0
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS RecentCommentCount,
        STRING_AGG(DISTINCT SUBSTRING(c.Text FROM 1 FOR 50), ' || ') AS RecentCommentSnippets,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days') AND c.UserId IS NOT NULL
    GROUP BY c.UserId
),
MainUserData AS (
    SELECT
        upa.UserId,
        upa.DisplayName,
        upa.UserCreationDate,
        upa.Reputation,
        upa.UserViews,
        upa.UserLocation,
        upa.TotalPostsCount,
        upa.TotalPostsScore,
        upa.AveragePostScore,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.LastPostCreationDate,
        upa.FirstPostCreationDate,
        upa.TotalFavoriteCount,
        tpb.TagName AS MostScoredTag,
        tpb.TagScoreSum AS MostScoredTagScore,
        uca.RecentCommentCount,
        uca.RecentCommentSnippets,
        uca.LastCommentDate,
        MAX(CASE WHEN phd.IsClosedAsDuplicate THEN phd.HistoryDate END) AS LastClosedAsDuplicateDate,
        MAX(CASE WHEN phd.IsMigratedAway THEN phd.HistoryDate END) AS LastMigratedAwayDate,
        RANK() OVER (ORDER BY upa.Reputation DESC, upa.TotalPostsScore DESC) AS GlobalReputationRank,
        NTILE(10) OVER (PARTITION BY upa.UserLocation ORDER BY upa.AveragePostScore DESC) AS AvgScoreLocationDecile,
        LAG(upa.LastPostCreationDate, 1, TIMESTAMP '1970-01-01') OVER (PARTITION BY upa.UserLocation ORDER BY upa.LastPostCreationDate) AS PreviousUserLastPostInLocation,
        (
            SELECT COUNT(b.Id)
            FROM Badges b
            WHERE b.UserId = upa.UserId
              AND b.Class = 1
              AND b.Date < upa.FirstPostCreationDate
        ) AS GoldBadgesBeforeFirstPost,
        upa.UserUpVotesGiven,
        upa.UserDownVotesGiven,
        upa.UserCreationDate AS __UserCreationDate_for_grouping,
        upa.TotalPostsCount AS __TotalPostsCount_for_grouping
    FROM UserPostAggregates upa
    LEFT JOIN Posts p_owned ON upa.UserId = p_owned.OwnerUserId
    LEFT JOIN PostHistoryDetails phd ON p_owned.Id = phd.PostId
    LEFT JOIN TagPerformanceByUser tpb ON upa.UserId = tpb.UserId AND tpb.rn_top_tag = 1
    LEFT JOIN UserCommentActivity uca ON upa.UserId = uca.UserId
    GROUP BY
        upa.UserId, upa.DisplayName, upa.UserCreationDate, upa.Reputation, upa.UserViews, upa.UserLocation,
        upa.TotalPostsCount, upa.TotalPostsScore, upa.AveragePostScore, upa.QuestionCount, upa.AnswerCount,
        upa.LastPostCreationDate, upa.FirstPostCreationDate, upa.TotalFavoriteCount,
        tpb.TagName, tpb.TagScoreSum, uca.RecentCommentCount, uca.RecentCommentSnippets, uca.LastCommentDate,
        upa.UserUpVotesGiven, upa.UserDownVotesGiven, upa.UserCreationDate, upa.TotalPostsCount
)
SELECT
    m.UserId,
    m.DisplayName,
    m.UserLocation,
    m.Reputation,
    m.GlobalReputationRank,
    m.AvgScoreLocationDecile,
    m.GoldBadgesBeforeFirstPost,
    m.MostScoredTag,
    m.MostScoredTagScore,
    m.QuestionCount,
    m.AnswerCount,
    COALESCE(m.RecentCommentCount, 0) AS UserRecentCommentCount,
    m.RecentCommentSnippets,
    m.LastClosedAsDuplicateDate,
    m.LastMigratedAwayDate,
    NULLIF(m.Reputation, 0) / NULLIF(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - m.UserCreationDate)) / (60 * 60 * 24 * 365.25), 0.001) AS AvgReputationPerYear,
    CASE
        WHEN m.TotalPostsCount > 0 AND (SELECT AVG(CHAR_LENGTH(p.Body)) FROM Posts p WHERE p.OwnerUserId = m.UserId AND p.PostTypeId = 1) > 1000 THEN 'Long Q&A User'
        WHEN m.TotalPostsCount > 0 AND (SELECT AVG(CHAR_LENGTH(p.Body)) FROM Posts p WHERE p.OwnerUserId = m.UserId AND p.PostTypeId = 1) BETWEEN 200 AND 1000 THEN 'Medium Q&A User'
        WHEN m.TotalPostsCount > 0 AND (SELECT AVG(CHAR_LENGTH(p.Body)) FROM Posts p WHERE p.OwnerUserId = m.UserId AND p.PostTypeId = 1) < 200 THEN 'Short Q&A User'
        ELSE 'No Questions'
    END AS QuestionBodyLengthCategory,
    CASE
        WHEN m.Reputation > 50000
             AND m.GoldBadgesBeforeFirstPost >= 3
             AND m.QuestionCount >= 20
             AND m.AnswerCount >= 50
             AND m.TotalPostsScore > 1000
             AND m.LastClosedAsDuplicateDate IS NULL
             AND m.LastMigratedAwayDate IS NOT NULL THEN 'Elite Migrator'
        WHEN m.Reputation > 10000
             AND m.MostScoredTag IS NOT NULL
             AND m.MostScoredTagScore > 500
             AND m.AvgScoreLocationDecile <= 3
             AND m.LastClosedAsDuplicateDate IS NOT NULL THEN 'Focused Duplicator'
        ELSE 'General Contributor'
    END AS UserProfileType,
    UPPER(SUBSTRING(m.DisplayName FROM 1 FOR 3)) || LPAD(SUBSTRING(m.DisplayName FROM (CASE WHEN CHAR_LENGTH(m.DisplayName) >= 3 THEN CHAR_LENGTH(m.DisplayName)-2 ELSE 1 END) FOR 3), 3, '*') AS DisplayNameSignature,
    NULLIF(m.UserUpVotesGiven, m.UserDownVotesGiven) AS UpVoteDownVoteDifference
FROM MainUserData m
WHERE m.Reputation > 100
  AND m.TotalPostsCount > 5
  AND m.FirstPostCreationDate IS NOT NULL
  AND m.QuestionCount > 0
  AND EXISTS (
      SELECT 1
      FROM PostHistory ph_check
      INNER JOIN Posts p_check ON ph_check.PostId = p_check.Id
      WHERE p_check.OwnerUserId = m.UserId
        AND ph_check.UserId = m.UserId
        AND ph_check.PostHistoryTypeId IN (4, 5, 6)
      GROUP BY p_check.OwnerUserId
      HAVING COUNT(ph_check.Id) > 5
  )
EXCEPT
SELECT
    m.UserId,
    m.DisplayName,
    m.UserLocation,
    m.Reputation,
    m.GlobalReputationRank,
    m.AvgScoreLocationDecile,
    m.GoldBadgesBeforeFirstPost,
    m.MostScoredTag,
    m.MostScoredTagScore,
    m.QuestionCount,
    m.AnswerCount,
    COALESCE(m.RecentCommentCount, 0) AS UserRecentCommentCount,
    m.RecentCommentSnippets,
    m.LastClosedAsDuplicateDate,
    m.LastMigratedAwayDate,
    NULLIF(m.Reputation, 0) / NULLIF(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - m.UserCreationDate)) / (60 * 60 * 24 * 365.25), 0.001) AS AvgReputationPerYear,
    CASE
        WHEN m.TotalPostsCount > 0 AND (SELECT AVG(CHAR_LENGTH(p.Body)) FROM Posts p WHERE p.OwnerUserId = m.UserId AND p.PostTypeId = 1) > 1000 THEN 'Long Q&A User'
        WHEN m.TotalPostsCount > 0 AND (SELECT AVG(CHAR_LENGTH(p.Body)) FROM Posts p WHERE p.OwnerUserId = m.UserId AND p.PostTypeId = 1) BETWEEN 200 AND 1000 THEN 'Medium Q&A User'
        WHEN m.TotalPostsCount > 0 AND (SELECT AVG(CHAR_LENGTH(p.Body)) FROM Posts p WHERE p.OwnerUserId = m.UserId AND p.PostTypeId = 1) < 200 THEN 'Short Q&A User'
        ELSE 'No Questions'
    END AS QuestionBodyLengthCategory,
    CASE
        WHEN m.Reputation > 50000
             AND m.GoldBadgesBeforeFirstPost >= 3
             AND m.QuestionCount >= 20
             AND m.AnswerCount >= 50
             AND m.TotalPostsScore > 1000
             AND m.LastClosedAsDuplicateDate IS NULL
             AND m.LastMigratedAwayDate IS NOT NULL THEN 'Elite Migrator'
        WHEN m.Reputation > 10000
             AND m.MostScoredTag IS NOT NULL
             AND m.MostScoredTagScore > 500
             AND m.AvgScoreLocationDecile <= 3
             AND m.LastClosedAsDuplicateDate IS NOT NULL THEN 'Focused Duplicator'
        ELSE 'General Contributor'
    END AS UserProfileType,
    UPPER(SUBSTRING(m.DisplayName FROM 1 FOR 3)) || LPAD(SUBSTRING(m.DisplayName FROM (CASE WHEN CHAR_LENGTH(m.DisplayName) >= 3 THEN CHAR_LENGTH(m.DisplayName)-2 ELSE 1 END) FOR 3), 3, '*') AS DisplayNameSignature,
    NULLIF(m.UserUpVotesGiven, m.UserDownVotesGiven) AS UpVoteDownVoteDifference
FROM MainUserData m
INNER JOIN Posts p_downvote ON m.UserId = p_downvote.OwnerUserId AND p_downvote.PostTypeId = 1
WHERE p_downvote.Score < -5
GROUP BY
    m.UserId, m.DisplayName, m.UserLocation, m.Reputation, m.GlobalReputationRank, m.AvgScoreLocationDecile,
    m.GoldBadgesBeforeFirstPost, m.MostScoredTag, m.MostScoredTagScore, m.QuestionCount, m.AnswerCount,
    m.RecentCommentCount, m.RecentCommentSnippets, m.LastClosedAsDuplicateDate, m.LastMigratedAwayDate,
    m.UserCreationDate, m.TotalPostsCount, m.UserUpVotesGiven, m.UserDownVotesGiven, m.TotalPostsScore
HAVING SUM(CASE WHEN p_downvote.Score < -5 THEN 1 ELSE 0 END) >= 2;