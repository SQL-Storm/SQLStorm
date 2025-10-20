-- {"query": "19088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2708} 
WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentActivity,
        RANK() OVER (ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC) AS ReputationPostRank
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    WHERE u.CreationDate >= '2020-01-01'
        AND u.Reputation > 500
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
PostActivityMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.OwnerUserId,
        COUNT(DISTINCT ph_edit.Id) AS EditCount,
        COUNT(DISTINCT CASE WHEN ph_close.PostHistoryTypeId = 10 THEN ph_close.Id ELSE NULL END) AS CloseEventCount,
        COUNT(DISTINCT CASE WHEN ph_reopen.PostHistoryTypeId = 11 THEN ph_reopen.Id ELSE NULL END) AS ReopenEventCount,
        MAX(CASE WHEN ph_close.PostHistoryTypeId = 10 AND crt.Name IS NOT NULL THEN crt.Name ELSE 'N/A' END) AS LastCloseReason,
        COUNT(DISTINCT pl_linked.Id) AS LinkedPostsCount,
        COUNT(DISTINCT pl_dup.Id) AS DuplicatePostsCount,
        (SELECT MIN(ph_initial_body.CreationDate)
         FROM PostHistory AS ph_initial_body
         WHERE ph_initial_body.PostId = p.Id
           AND ph_initial_body.PostHistoryTypeId = 2) AS InitialBodyCreationDate,
        STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, 10), ', ') FILTER (WHERE t.TagName IS NOT NULL) AS AssociatedTagsSummary
    FROM Posts AS p
    LEFT JOIN PostHistory AS ph_edit ON p.Id = ph_edit.PostId
        AND ph_edit.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    LEFT JOIN PostHistory AS ph_close ON p.Id = ph_close.PostId
        AND ph_close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory AS ph_reopen ON p.Id = ph_reopen.PostId
        AND ph_reopen.PostHistoryTypeId = 11
    LEFT JOIN CloseReasonTypes AS crt ON CAST(ph_close.Comment AS SMALLINT) = crt.Id
    LEFT JOIN PostLinks AS pl_linked ON p.Id = pl_linked.PostId
        AND pl_linked.LinkTypeId = 1
    LEFT JOIN PostLinks AS pl_dup ON p.Id = pl_dup.PostId
        AND pl_dup.LinkTypeId = 3
    LEFT JOIN Tags AS t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= '2021-01-01'
    GROUP BY
        p.Id, p.PostTypeId, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId
    HAVING COUNT(DISTINCT ph_edit.Id) > 0 OR COUNT(DISTINCT ph_close.Id) > 0
),
TagInfluenceScores AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        SUM(p_flat_tags.Score) AS TotalTagScore,
        AVG(p_flat_tags.ViewCount) AS AvgTagViewCount,
        COUNT(DISTINCT p_flat_tags.Id) AS TotalPostsWithTag,
        AVG(ues.Reputation) AS AvgOwnerReputationForTag,
        SUM(pam.EditCount) AS TotalEditsForTagPosts,
        NTILE(5) OVER (ORDER BY SUM(p_flat_tags.Score) DESC, AVG(ues.Reputation) DESC, COUNT(DISTINCT p_flat_tags.Id) DESC) AS TagScorePercentile
    FROM Tags AS t
    INNER JOIN (
        SELECT DISTINCT
            p_inner.Id,
            p_inner.CreationDate,
            p_inner.PostTypeId,
            p_inner.Score,
            p_inner.ViewCount,
            p_inner.OwnerUserId,
            UNNEST(STRING_TO_ARRAY(SUBSTRING(p_inner.Tags, 2, LENGTH(p_inner.Tags)-2), '><')) AS ExtractedTag
        FROM Posts AS p_inner
        WHERE p_inner.Tags IS NOT NULL AND LENGTH(p_inner.Tags) > 2
    ) AS p_flat_tags ON t.TagName = p_flat_tags.ExtractedTag
    INNER JOIN UserEngagementSummary AS ues ON p_flat_tags.OwnerUserId = ues.UserId
    INNER JOIN PostActivityMetrics AS pam ON p_flat_tags.Id = pam.PostId
    WHERE p_flat_tags.PostTypeId = 1
      AND p_flat_tags.CreationDate >= '2022-01-01'
    GROUP BY
        t.Id, t.TagName
    HAVING COUNT(DISTINCT p_flat_tags.Id) > 10
),
ControversialContent AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        CAST(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DECIMAL) /
        NULLIF(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END), 0) AS DownVoteRatio,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS ClosedHistoryCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS ReopenedHistoryCount,
        (CAST(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS DECIMAL) +
         CAST(COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) AS DECIMAL)) /
        NULLIF(COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (10,11)), 0) AS CloseReopenActivityRatio
    FROM Posts AS p
    LEFT JOIN Votes AS v ON p.Id = v.PostId
    LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId
        AND ph.PostHistoryTypeId IN (10, 11)
    WHERE p.CreationDate >= '2023-01-01'
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId
    HAVING
        (SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) > 5 AND CAST(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DECIMAL) / NULLIF(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END), 0) > 0.3)
        OR (COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) + COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.Id END) > 2)
)
SELECT
    UES.UserName,
    UES.Reputation,
    PAM.PostId,
    PAM.Title,
    PAM.PostScore,
    PAM.ViewCount,
    PAM.EditCount,
    PAM.CloseEventCount,
    PAM.ReopenEventCount,
    COALESCE(CC.DownVoteRatio, 0.0) AS DownVoteRatio,
    COALESCE(CC.CloseReopenActivityRatio, 0.0) AS CloseReopenActivityRatio,
    TIS.TagName AS PrimaryAssociatedTag,
    TIS.TagScorePercentile,
    CASE
        WHEN PAM.CloseEventCount > 0 AND COALESCE(CC.DownVoteRatio, 0.0) > 0.4 THEN 'Highly Controversial & Closed'
        WHEN PAM.EditCount > 5 AND PAM.PostScore < 0 THEN 'Frequently Edited Low Score Post'
        WHEN UES.ReputationPostRank <= 100 AND TIS.TagScorePercentile = 1 THEN 'Top User - Top Tag Contributor'
        WHEN UES.Reputation IS NULL THEN 'Unknown Owner Activity'
        WHEN PAM.AssociatedTagsSummary LIKE '%javascript%' AND PAM.PostScore > 50 THEN 'High Value JS Content'
        ELSE 'Regular Activity'
    END AS PostAssessment,
    COALESCE(PAM.LastCloseReason, 'No specific close reason') AS DetailedCloseReason,
    CONCAT(
        'Post Activity: Edits(', PAM.EditCount, ') - Closes(', PAM.CloseEventCount, ') - Links(', PAM.LinkedPostsCount, ') - Duplicates(', PAM.DuplicatePostsCount, ')'
    ) AS ActivitySummaryString,
    (SELECT COUNT(DISTINCT ph_all.Id)
     FROM PostHistory AS ph_all
     WHERE ph_all.PostId = PAM.PostId
       AND ph_all.CreationDate BETWEEN PAM.PostCreationDate AND PAM.PostCreationDate + INTERVAL '3 months'
       AND ph_all.PostHistoryTypeId IN (1,2,3,4,5,6,10,11,12,13)) AS Initial3MonthsHistoryCount
FROM UserEngagementSummary AS UES
INNER JOIN PostActivityMetrics AS PAM ON UES.UserId = PAM.OwnerUserId
FULL OUTER JOIN ControversialContent AS CC ON PAM.PostId = CC.PostId
LEFT JOIN TagInfluenceScores AS TIS ON PAM.Tags LIKE '%' || '<' || TIS.TagName || '>' || '%'
WHERE
    (PAM.PostTypeId = 1 AND PAM.ViewCount > 1000 AND PAM.PostScore > 5 AND COALESCE(CC.DownVoteRatio, 0.0) < 0.5)
    OR
    (PAM.PostTypeId = 2 AND PAM.EditCount > 2 AND UES.Reputation > 1000 AND PAM.AssociatedTagsSummary IS NOT NULL)
ORDER BY
    UES.Reputation DESC,
    PAM.PostScore DESC,
    PAM.EditCount DESC
LIMIT 1000;