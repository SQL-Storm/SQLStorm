-- {"query": "4364.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1806} 

WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY SUBSTRING(CAST(u.CreationDate AS DATE), 1, 7) ORDER BY u.Reputation DESC) AS MonthlyReputationRank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) AS PreviousUserReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.DisplayName IS NOT NULL
      AND u.EmailHash IS NOT NULL
      AND u.Location LIKE '%USA%'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 50 OR COUNT(DISTINCT c.Id) > 100
),
PostVoteAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pt.Name AS PostType,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        CASE
            WHEN p.AnswerCount IS NULL THEN 0
            ELSE p.AnswerCount
        END AS AnswerCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountOnPost,
        AVG(CAST(v.VoteTypeId AS DECIMAL)) OVER (PARTITION BY p.Id) AS AvgVoteTypeForPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotesForPost,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotesForPost,
        COUNT(pv.Id) AS PostHistoryEdits
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory pv ON p.Id = pv.PostId AND pv.PostHistoryTypeId IN (5, 6) -- Edit Body, Edit Tags
    WHERE p.Score > 10
      AND p.ViewCount > 1000
      AND p.ContentLicense IS NOT NULL
      AND DATE_PART('year', p.CreationDate) >= 2020
    GROUP BY p.Id, p.Title, pt.Name, u.DisplayName, p.CreationDate, p.Score, p.AnswerCount, p.ViewCount, p.ContentLicense
),
AggregatedPostMetrics AS (
    SELECT
        pva.PostId,
        pva.Title,
        pva.PostType,
        pva.OwnerDisplayName,
        pva.CreationDate,
        pva.Score,
        pva.AnswerCount,
        pva.CommentCountOnPost,
        pva.UpVotesForPost,
        pva.DownVotesForPost,
        pva.PostHistoryEdits,
        CASE
            WHEN pva.Score < 0 THEN 'Negative Score'
            WHEN pva.Score BETWEEN 0 AND 10 THEN 'Low Score'
            WHEN pva.Score > 10 AND pva.AnswerCount > 5 THEN 'High Score & Many Answers'
            ELSE 'Other'
        END AS ScoreCategory,
        COALESCE(pva.OwnerDisplayName, 'Community') AS DisplayOwner,
        UPPER(SUBSTRING(pva.Title FROM 1 FOR 3)) AS TitlePrefix,
        CASE
            WHEN pva.PostHistoryEdits > (SELECT AVG(PostHistoryEdits) FROM PostVoteAnalysis) THEN 'High Edit Volume'
            ELSE 'Standard Edit Volume'
        END AS EditVolumeStatus
    FROM PostVoteAnalysis pva
),
HighReputationUsers AS (
    SELECT UserId, DisplayName, Reputation
    FROM RankedUserActivity
    WHERE ReputationRank <= 100
),
AllPostDetails AS (
    SELECT
        apm.PostId,
        apm.Title,
        apm.PostType,
        apm.DisplayOwner,
        apm.CreationDate,
        apm.Score,
        apm.AnswerCount,
        apm.CommentCountOnPost,
        apm.UpVotesForPost,
        apm.DownVotesForPost,
        apm.ScoreCategory,
        apm.TitlePrefix,
        apm.EditVolumeStatus,
        CASE WHEN hru.UserId IS NOT NULL THEN 'High Reputation' ELSE 'Standard Reputation' END AS OwnerReputationStatus,
        (SELECT Name FROM PostHistoryTypes WHERE Id = (SELECT PostHistoryTypeId FROM PostHistory ph WHERE ph.PostId = apm.PostId ORDER BY ph.CreationDate DESC LIMIT 1)) AS LastPostHistoryAction
    FROM AggregatedPostMetrics apm
    LEFT JOIN HighReputationUsers hru ON apm.DisplayOwner = hru.DisplayName
)
SELECT
    apd.PostId,
    apd.Title,
    apd.PostType,
    apd.DisplayOwner,
    apd.CreationDate,
    apd.Score,
    apd.AnswerCount,
    apd.CommentCountOnPost,
    apd.UpVotesForPost,
    apd.DownVotesForPost,
    apd.ScoreCategory,
    apd.TitlePrefix,
    apd.EditVolumeStatus,
    apd.OwnerReputationStatus,
    apd.LastPostHistoryAction,
    RU.Reputation AS OwnerReputation,
    ru.MonthlyReputationRank AS OwnerMonthlyReputationRank,
    CASE
        WHEN apd.Score > 0 AND apd.AnswerCount > apd.CommentCountOnPost THEN 'Popular Question'
        WHEN apd.Score < 0 AND apd.PostType = 'Question' THEN 'Controversial Question'
        WHEN apd.PostType = 'Answer' AND apd.Score >= apd.AnswerCount THEN 'Highly Rated Answer'
        ELSE 'Standard Post'
    END AS PostEngagementStatus,
    COALESCE(apd.Score + apd.AnswerCount + apd.CommentCountOnPost, 0) AS TotalEngagementScore,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = apd.PostId AND pl.LinkTypeId = 3) THEN 'Has Duplicate Link'
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = apd.PostId AND pl.LinkTypeId = 1) THEN 'Is Linked'
        ELSE 'No External Links'
    END AS LinkStatus,
    CASE
        WHEN apd.OwnerReputationStatus = 'High Reputation' AND apd.EditVolumeStatus = 'High Edit Volume' THEN 'Influential Contributor'
        WHEN apd.ScoreCategory = 'High Score & Many Answers' AND apd.OwnerReputationStatus = 'High Reputation' THEN 'Top Performer'
        ELSE 'Standard Contributor'
    END AS ContributorTier
FROM AllPostDetails apd
LEFT JOIN RankedUserActivity ru ON apd.DisplayOwner = ru.DisplayName
WHERE apd.Score > 5
   OR apd.AnswerCount > 10
ORDER BY apd.Score DESC, apd.CreationDate ASC
LIMIT 100;
