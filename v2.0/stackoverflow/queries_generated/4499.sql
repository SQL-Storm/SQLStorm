-- {"query": "4499.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1197} 
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edits and Rollbacks
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
        MAX(u.LastAccessDate) AS LastAccessDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostType,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.ClosedDate,
        p.CommunityOwnedDate,
        COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
        CASE WHEN p.ClosedDate IS NOT NULL THEN DATEDIFF(day, p.CreationDate, p.ClosedDate) ELSE NULL END AS DaysToClose,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN DATEDIFF(day, p.CreationDate, p.CommunityOwnedDate) ELSE NULL END AS DaysToCommunityOwnership,
        CASE WHEN p.OwnerUserId IS NOT NULL THEN
            (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = p.OwnerUserId AND PostTypeId = 1)
        ELSE 0 END AS OwnerQuestionCount,
        (SELECT COUNT(*) FROM Comments WHERE PostId = p.Id AND UserId IS NOT NULL) AS CommenterCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
HighReputationUsers AS (
    SELECT Id, DisplayName
    FROM Users
    WHERE Reputation > 100000
),
PostEditFrequency AS (
    SELECT
        PostId,
        COUNT(*) AS EditCount,
        AVG(rn) AS AvgEditRankForUser -- Lower is more recent
    FROM RankedPostEdits
    GROUP BY PostId
    HAVING COUNT(*) > 1
)
SELECT
    pd.PostId,
    pd.PostType,
    pd.Title,
    pd.Tags,
    pd.Score,
    pd.ViewCount,
    pd.AnswerCount,
    pd.CommentCount,
    pd.FavoriteCount,
    pd.CreationDate,
    pd.ClosedDate,
    pd.CommunityOwnedDate,
    pd.OwnerDisplayName,
    pd.DaysToClose,
    pd.DaysToCommunityOwnership,
    pd.OwnerQuestionCount,
    pd.CommenterCount,
    COALESCE(ohr.DisplayName, 'N/A') AS HighReputationOwner,
    pef.EditCount AS EditFrequency,
    pef.AvgEditRankForUser,
    CASE
        WHEN pd.Score > 100 AND pd.AnswerCount > 10 THEN 'Popular & Highly Answered'
        WHEN pd.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN pd.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
        ELSE 'Standard Post'
    END AS PostCategory,
    ua.TotalPosts AS OwnerTotalPosts,
    ua.TotalComments AS OwnerTotalComments,
    ua.TotalUpVotesReceived AS OwnerTotalUpVotesReceived,
    ua.TotalDownVotesReceived AS OwnerTotalDownVotesReceived,
    ua.LastAccessDate AS OwnerLastAccessDate,
    CASE WHEN pd.Tags LIKE '%<sql>%' THEN 'Contains SQL Tag' ELSE 'No SQL Tag' END AS HasSqlTag,
    LOWER(SUBSTRING(pd.Title, 1, 3)) AS TitlePrefix
FROM PostDetails pd
LEFT JOIN HighReputationUsers ohr ON pd.OwnerUserId = ohr.Id
LEFT JOIN PostEditFrequency pef ON pd.PostId = pef.PostId
LEFT JOIN UserActivity ua ON pd.OwnerUserId = ua.UserId
WHERE pd.Score IS NOT NULL
  AND pd.ViewCount > 1000
  AND (pd.Tags LIKE '%<performance>%' OR pd.Tags LIKE '%<sql>%' OR pd.Tags LIKE '%<benchmarking>%')
ORDER BY pd.Score DESC, pd.ViewCount DESC
LIMIT 100;