-- {"query": "1020.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2532}
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS TotalUpVotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS TotalDownVotesGiven,
        CAST(FLOOR((EXTRACT(EPOCH FROM TIMESTAMP '2024-10-01 12:34:56') - EXTRACT(EPOCH FROM u.CreationDate)) / (60.0 * 60.0 * 24.0)) AS INTEGER) AS AccountAgeDays,
        MAX(ph.CreationDate) AS LastUserEditDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        CASE WHEN MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) = 1 THEN TRUE ELSE FALSE END AS HasGoldBadge,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS InitialPostScore,
        p.ViewCount,
        p.AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCountOnPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceivedOnPost,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceivedOnPost,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateLinkCount,
        COUNT(DISTINCT CASE WHEN pl_rev.LinkTypeId = 3 THEN pl_rev.PostId END) AS IsDuplicatedByCount,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        (SELECT COUNT(ph_inner.Id) FROM PostHistory ph_inner WHERE ph_inner.PostId = p.Id AND ph_inner.PostHistoryTypeId IN (4,5,6)) AS EditHistoryCount,
        p.Title,
        p.Tags,
        p.Body,
        p.LastActivityDate
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN PostLinks pl_rev ON p.Id = pl_rev.RelatedPostId
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.AcceptedAnswerId, p.Title, p.Tags, p.Body, p.LastActivityDate
),
RecentModeratorActivity AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS ActionDate,
        ph.UserId AS ModeratorId,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
      AND ph.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 days')
)
SELECT
    p.Id AS PostId,
    pt.Name AS PostTypeName,
    COALESCE(pem.Title, 'No Title') AS PostTitle,
    pem.PostCreationDate,
    COALESCE(u.Id, -1) AS OwnerUserId,
    COALESCE(uas.DisplayName, 'Community/Deleted User') AS OwnerDisplayName,
    COALESCE(uas.Reputation, 0) AS OwnerReputation,
    uas.AccountAgeDays AS OwnerAccountAgeDays,
    COALESCE(pem.InitialPostScore, 0) AS InitialPostScore,
    (pem.UpVotesReceivedOnPost - pem.DownVotesReceivedOnPost) AS NetVotesReceived,
    pem.CommentCountOnPost AS CommentCount,
    pem.EditHistoryCount AS PostEditCount,
    NULLIF(pem.ViewCount, 0) AS PostViewCountNormalized,
    CASE
        WHEN pem.HasAcceptedAnswer = 1 THEN 'Accepted'
        WHEN p.AcceptedAnswerId IS NULL AND p.PostTypeId = 1 THEN 'NoAccepted'
        ELSE 'N/A'
    END AS AcceptedAnswerStatus,
    TRIM(REPLACE(REPLACE(REPLACE(
        SUBSTR(pem.Tags, 2, CASE WHEN LENGTH(pem.Tags) >= 2 THEN LENGTH(pem.Tags)-2 ELSE 0 END), '><', ', '), '><', ', '), ', ,', ',')) AS CleanedTags,
    (CASE WHEN pem.Tags IS NOT NULL AND LENGTH(pem.Tags) > 2
          THEN (LENGTH(pem.Tags) - LENGTH(REPLACE(pem.Tags, '><', '')) ) + 0
          ELSE 0 END) AS TagCount,
    (SELECT COUNT(t.Id)
     FROM Tags t
     WHERE pem.Tags IS NOT NULL
       AND t.TagName IS NOT NULL
       AND t.TagName <> ''
       AND POSITION(t.TagName IN pem.Tags) > 0
    ) AS ValidTagsPresent,
    CASE
        WHEN pem.Body LIKE '%<pre><code>%' OR pem.Body LIKE '%```%' THEN 'ContainsCodeSnippet'
        WHEN LENGTH(pem.Body) > 5000 THEN 'VeryLongBody'
        WHEN LENGTH(pem.Body) BETWEEN 500 AND 5000 THEN 'StandardLengthBody'
        ELSE 'ShortBody'
    END AS PostBodyAnalysis,
    (SELECT AVG(p_corr.Score)
     FROM Posts p_corr
     INNER JOIN Users u_corr ON p_corr.OwnerUserId = u_corr.Id
     WHERE p_corr.Id != p.Id
       AND p_corr.PostTypeId = p.PostTypeId
       AND p_corr.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')
       AND u_corr.Reputation BETWEEN u.Reputation * 0.8 AND u.Reputation * 1.2
       AND u_corr.LastAccessDate > (u.LastAccessDate - INTERVAL '30 days')
    ) AS AvgScoreSimilarActiveUsersPosts,
    (SELECT COUNT(c_corr.Id)
     FROM Comments c_corr
     INNER JOIN Users u_commenter ON c_corr.UserId = u_commenter.Id
     WHERE c_corr.PostId = p.Id
       AND u_commenter.CreationDate < p.CreationDate
    ) AS CommentCountByEstablishedUsers,
    RANK() OVER (PARTITION BY p.PostTypeId ORDER BY (pem.UpVotesReceivedOnPost - pem.DownVotesReceivedOnPost) DESC, pem.LastActivityDate DESC) AS PostRankByNetVotesAndActivity,
    AVG(uas.Reputation) OVER (ORDER BY uas.UserCreationDate, uas.UserId ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAvgReputationAtPostTime,
    CASE
        WHEN uas.UserId IS NULL THEN 'CommunityOrDeleted'
        WHEN uas.Reputation >= 20000 AND uas.HasGoldBadge THEN 'EliteContributor'
        WHEN uas.Reputation >= 5000 AND uas.TotalPosts > 100 THEN 'ProdigiousAuthor'
        WHEN uas.AccountAgeDays < 90 AND uas.TotalPosts < 5 AND uas.Reputation < 100 THEN 'NewbieUser'
        ELSE 'RegularUser'
    END AS OwnerClassification,
    rma.ActionDate AS LastModeratorActionDate,
    phist.Name AS LastModeratorActionType,
    (SELECT COUNT(DISTINCT s_u.Id) FROM Users s_u WHERE s_u.Id = u.Id AND s_u.Id IN (
        SELECT OwnerUserId FROM Posts WHERE OwnerUserId IS NOT NULL
        EXCEPT
        SELECT UserId FROM Votes WHERE UserId IS NOT NULL
    )) > 0 AS IsPosterWhoNeverVoted,
    ((CASE WHEN pem.DuplicateLinkCount > 0 OR pem.IsDuplicatedByCount > 0 OR (p.ClosedDate IS NOT NULL) THEN 1 ELSE 0 END) = 1) AS HasDuplicateOrIsClosed
FROM Posts p
INNER JOIN PostEngagementMetrics pem ON p.Id = pem.PostId
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN UserActivitySummary uas ON u.Id = uas.UserId
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN RecentModeratorActivity rma ON p.Id = rma.PostId AND rma.rn = 1
LEFT JOIN PostHistoryTypes phist ON rma.PostHistoryTypeId = phist.Id
WHERE p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3 years')
  AND (p.ViewCount IS NULL OR p.ViewCount > 50)
  AND (pem.Tags LIKE '%<sql>%' OR pem.Tags LIKE '%<database>%')
  AND (pem.UpVotesReceivedOnPost + pem.DownVotesReceivedOnPost > 5)
  AND p.PostTypeId IN (1, 2, 4, 5)
ORDER BY
    OwnerReputation DESC,
    NetVotesReceived DESC,
    pem.PostCreationDate DESC
LIMIT 1000;