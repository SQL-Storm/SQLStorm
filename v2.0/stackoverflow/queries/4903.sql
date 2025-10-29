-- {"query": "4903.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1164}
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        CASE
            WHEN p.OwnerUserId IS NULL THEN 'Community'
            ELSE COALESCE(u.DisplayName, 'Unknown User')
        END AS OwnerDisplayName,
        COALESCE(u.Reputation, 0) AS OwnerReputation,
        CASE
            WHEN p.OwnerUserId IS NULL THEN 0
            ELSE EXTRACT(YEAR FROM AGE(TIMESTAMP '2024-10-01 12:34:56', u.CreationDate))
        END AS UserAgeInYears,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5) AS HighScoreCommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
        COALESCE(rp.rn, 0) AS RecentEditRankForUser
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN RankedPostEdits rp ON p.Id = rp.PostId AND p.OwnerUserId = rp.UserId AND rp.rn = 1
    WHERE p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days')
),
TopUsersByReputation AS (
    SELECT
        Id AS UserId,
        DisplayName,
        Reputation,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS rep_rank
    FROM Users
    WHERE CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 days')
)
SELECT
    upa.PostId,
    upa.PostTypeName,
    upa.OwnerDisplayName,
    upa.OwnerReputation,
    upa.UserAgeInYears,
    upa.PostCreationDate,
    upa.PostScore,
    upa.PostViewCount,
    upa.AnswerCount,
    upa.CommentCount,
    upa.FavoriteCount,
    upa.ClosedDate,
    upa.HighScoreCommentCount,
    upa.UpVoteCount,
    upa.DownVoteCount,
    upa.DuplicateLinkCount,
    upa.RecentEditRankForUser,
    tur.rep_rank AS OwnerReputationRank,
    CASE
        WHEN upa.PostScore > 100 THEN 'HighScore'
        WHEN upa.AnswerCount > 10 THEN 'Popular'
        WHEN upa.CommentCount > 20 THEN 'TalkedAbout'
        ELSE 'Standard'
    END AS PostCategory,
    UPPER(SUBSTRING(upa.OwnerDisplayName FROM 1 FOR 3)) AS DisplayNamePrefix,
    CASE
        WHEN upa.PostCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '7 days') THEN 'Old'
        WHEN upa.PostCreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '7 days') THEN 'Recent'
        ELSE 'UnknownAge'
    END AS PostAgeGroup,
    CASE
        WHEN upa.ClosedDate IS NOT NULL AND upa.ClosedDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days') THEN 'RecentlyClosed'
        WHEN upa.ClosedDate IS NOT NULL THEN 'PreviouslyClosed'
        ELSE 'Open'
    END AS ClosureStatus,
    (CHAR_LENGTH(upa.PostTypeName) + CHAR_LENGTH(upa.OwnerDisplayName)) AS CombinedLengthMetric,
    upa.OwnerUserId
FROM UserPostActivity upa
LEFT JOIN TopUsersByReputation tur ON upa.OwnerUserId = tur.UserId
WHERE upa.OwnerReputation > 5000
  AND upa.PostScore >= 0
  AND upa.UserAgeInYears > 0
  AND upa.PostViewCount > (upa.OwnerReputation / 1000.0)
  AND upa.RecentEditRankForUser <= 3
ORDER BY upa.PostScore DESC, upa.PostCreationDate DESC
LIMIT 1000;