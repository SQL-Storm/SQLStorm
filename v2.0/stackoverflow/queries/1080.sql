-- {"query": "1080.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3121}
WITH InfluentialUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.Views AS UserViews,
        COUNT(b.Id) AS TotalBadges,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        NTILE(4) OVER (ORDER BY u.Reputation DESC) AS ReputationQuartile,
        FIRST_VALUE(u.DisplayName) OVER (ORDER BY u.Reputation DESC) AS OverallTopRepUser
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation >= 10000
      AND u.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '6' YEAR)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views
    HAVING COUNT(b.Id) > 5
),
PostBodyMetrics AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        LENGTH(COALESCE(p.Body, '')) AS BodyLength,
        LENGTH(COALESCE(p.Title, '')) AS TitleLength,
        (CASE WHEN COALESCE(p.Body, '') LIKE '%<pre><code>%' OR COALESCE(p.Body, '') LIKE '%<code>%' THEN TRUE ELSE FALSE END) AS HasCodeBlock,
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2
            THEN (
                -- split tags like '<tag1><tag2>' into array and count elements in a dialect-neutral way
                (LENGTH(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags))) - LENGTH(REPLACE(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)), '><', '')) ) / LENGTH('><') + 1
            )
            ELSE 0
        END AS TagCount,
        (p.Score * 1.0 / NULLIF(LENGTH(COALESCE(p.Body, '')), 0)) AS ScoreDensity,
        p.Tags
    FROM Posts p
),
PostVoteSummary AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoriteVotes,
        (SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) * 1.0 / NULLIF(SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END), 0)) AS UpVoteRatio
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5)
    GROUP BY v.PostId
),
PostHistoryMetrics AS (
    SELECT
        ph.PostId,
        CAST(COUNT(DISTINCT ph.UserId) AS BIGINT) AS DistinctEditorCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate END) AS LastBodyEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosureDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL THEN CAST(ph.Comment AS SMALLINT) ELSE NULL END) AS CloseReasonId_IfClosed
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,10)
    GROUP BY ph.PostId
),
TagsExploded AS (
    -- Explode tags for posts used in the main queries. This approach is dialect-neutral: produce one row per tag per post.
    SELECT
      pbm.PostId,
      TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM SUBSTR(tag_str, 1))) AS value
    FROM PostBodyMetrics pbm,
    LATERAL (
      SELECT
        -- build a sequence of tag substrings by repeated splitting; use a simple method: replace leading/trailing <> then split on '><'
        regexp_split_to_table(
          CASE WHEN pbm.Tags IS NULL THEN '' ELSE SUBSTR(pbm.Tags, 2, LENGTH(pbm.Tags)-2) END,
          '><'
        ) AS tag_str
    ) t
)
SELECT
    'QuestionAnalysis' AS RecordType,
    iu.UserId,
    iu.DisplayName,
    iu.Reputation,
    iu.UserCreationDate,
    p.Id AS EntityId,
    p.Title AS EntityTitle,
    p.CreationDate AS EntityCreationDate,
    p.Score AS EntityScore,
    p.ViewCount AS EntityViewCount,
    p.AnswerCount AS EntityAnswerCount,
    p.FavoriteCount AS EntityFavoriteCount,
    pbm.BodyLength,
    pbm.TitleLength,
    pbm.HasCodeBlock,
    pbm.TagCount,
    pbm.ScoreDensity,
    COALESCE(pvs.TotalUpVotes, 0) AS TotalUpVotes,
    COALESCE(pvs.TotalDownVotes, 0) AS TotalDownVotes,
    COALESCE(pvs.UpVoteRatio, 0.0) AS UpVoteRatio,
    phm.DistinctEditorCount AS PostDistinctEditorCount,
    phm.LastBodyEditDate AS PostLastBodyEditDate,
    phm.ClosureDate AS PostClosureDate,
    crt.Name AS PostCloseReason,
    COALESCE( (SELECT AVG(c.Score) FROM Comments c WHERE c.PostId = p.Id), 0.0) AS AvgCommentScore,
    p.CommentCount AS PostCommentCount,
    COALESCE( (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8), 0.0) AS TotalBountyAmountOffered,
    CAST(COUNT(DISTINCT pl_linked.RelatedPostId) AS BIGINT) AS LinkedPostsCount,
    CAST(COUNT(DISTINCT pl_duplicate.RelatedPostId) AS BIGINT) AS DuplicatePostsCount,
    LAG(p.ViewCount, 1, 0) OVER (PARTITION BY iu.UserId ORDER BY p.CreationDate) AS PrevActivityMetric,
    NTILE(5) OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS PostRankMetric,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    COALESCE(p.CommunityOwnedDate, p.LastActivityDate, p.CreationDate) AS EffectiveLastActivityDate,
    STRING_AGG(DISTINCT te.value, ', ') FILTER (WHERE LOWER(te.value) LIKE '%sql%') AS KeywordRelatedTags
FROM InfluentialUsers iu
JOIN Posts p ON iu.UserId = p.OwnerUserId
JOIN PostBodyMetrics pbm ON p.Id = pbm.PostId
LEFT JOIN PostVoteSummary pvs ON p.Id = pvs.PostId
LEFT JOIN PostHistoryMetrics phm ON p.Id = phm.PostId
LEFT JOIN CloseReasonTypes crt ON phm.CloseReasonId_IfClosed = crt.Id
LEFT JOIN PostLinks pl_linked ON p.Id = pl_linked.PostId AND pl_linked.LinkTypeId = 1
LEFT JOIN PostLinks pl_duplicate ON p.Id = pl_duplicate.PostId AND pl_duplicate.LinkTypeId = 3
LEFT JOIN TagsExploded te ON pbm.PostId = te.PostId
WHERE p.PostTypeId = 1
  AND p.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '5' YEAR)
  AND p.Score > 5
GROUP BY
    iu.UserId, iu.DisplayName, iu.Reputation, iu.UserCreationDate,
    p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount,
    pbm.BodyLength, pbm.TitleLength, pbm.HasCodeBlock, pbm.TagCount, pbm.ScoreDensity, pbm.Tags,
    pvs.TotalUpVotes, pvs.TotalDownVotes, pvs.UpVoteRatio,
    phm.DistinctEditorCount, phm.LastBodyEditDate, phm.ClosureDate, crt.Name, p.CommentCount,
    p.ClosedDate, p.CommunityOwnedDate, p.LastActivityDate
UNION ALL
SELECT
    'AnswerAnalysis' AS RecordType,
    iu.UserId,
    iu.DisplayName,
    iu.Reputation,
    iu.UserCreationDate,
    pa.Id AS EntityId,
    qp.Title AS EntityTitle,
    pa.CreationDate AS EntityCreationDate,
    pa.Score AS EntityScore,
    qp.ViewCount AS EntityViewCount,
    NULL AS EntityAnswerCount,
    pa.FavoriteCount AS EntityFavoriteCount,
    pbm_a.BodyLength,
    NULL AS TitleLength,
    pbm_a.HasCodeBlock,
    pbm_q.TagCount AS TagCount,
    pbm_a.ScoreDensity,
    COALESCE(pvs_a.TotalUpVotes, 0) AS TotalUpVotes,
    COALESCE(pvs_a.TotalDownVotes, 0) AS TotalDownVotes,
    COALESCE(pvs_a.UpVoteRatio, 0.0) AS UpVoteRatio,
    phm_a.DistinctEditorCount AS PostDistinctEditorCount,
    phm_a.LastBodyEditDate AS PostLastBodyEditDate,
    NULL AS PostClosureDate,
    NULL AS PostCloseReason,
    COALESCE( (SELECT AVG(c.Score) FROM Comments c WHERE c.PostId = pa.Id), 0.0) AS AvgCommentScore,
    pa.CommentCount AS PostCommentCount,
    NULL AS TotalBountyAmountOffered,
    NULL AS LinkedPostsCount,
    NULL AS DuplicatePostsCount,
    LAG(pa.Score, 1, 0) OVER (PARTITION BY iu.UserId ORDER BY pa.CreationDate) AS PrevActivityMetric,
    RANK() OVER (PARTITION BY qp.Id ORDER BY pa.Score DESC, pa.CreationDate) AS PostRankMetric,
    CASE
        WHEN qp.AcceptedAnswerId = pa.Id THEN 'Accepted Answer'
        WHEN pa.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    COALESCE(pa.CommunityOwnedDate, pa.LastActivityDate, pa.CreationDate) AS EffectiveLastActivityDate,
    STRING_AGG(DISTINCT te_a.value, ', ') FILTER (WHERE LOWER(te_a.value) LIKE '%java%') AS KeywordRelatedTags
FROM InfluentialUsers iu
JOIN Posts pa ON iu.UserId = pa.OwnerUserId
JOIN Posts qp ON pa.ParentId = qp.Id
JOIN PostBodyMetrics pbm_a ON pa.Id = pbm_a.PostId
LEFT JOIN PostBodyMetrics pbm_q ON qp.Id = pbm_q.PostId
LEFT JOIN PostVoteSummary pvs_a ON pa.Id = pvs_a.PostId
LEFT JOIN PostHistoryMetrics phm_a ON pa.Id = phm_a.PostId
LEFT JOIN (
    -- explode tags for question (parent) post
    SELECT pbm.PostId, regexp_split_to_table(CASE WHEN pbm.Tags IS NULL THEN '' ELSE SUBSTR(pbm.Tags,2,LENGTH(pbm.Tags)-2) END, '><') AS value
    FROM PostBodyMetrics pbm
) te_a ON pbm_q.PostId = te_a.PostId
WHERE pa.PostTypeId = 2
  AND pa.CreationDate >= (CAST('2024-10-01' AS DATE) - INTERVAL '5' YEAR)
  AND (pa.Score >= 10 OR qp.AcceptedAnswerId = pa.Id)
GROUP BY
    iu.UserId, iu.DisplayName, iu.Reputation, iu.UserCreationDate,
    pa.Id, qp.Title, pa.CreationDate, pa.Score, qp.ViewCount, pa.FavoriteCount,
    pbm_a.BodyLength, pbm_a.HasCodeBlock, pbm_q.TagCount, pbm_a.ScoreDensity, pbm_q.Tags,
    pvs_a.TotalUpVotes, pvs_a.TotalDownVotes, pvs_a.UpVoteRatio,
    phm_a.DistinctEditorCount, phm_a.LastBodyEditDate, pa.CommentCount,
    qp.Id, qp.AcceptedAnswerId, pa.CommunityOwnedDate, pa.LastActivityDate
ORDER BY Reputation DESC, EntityCreationDate DESC
LIMIT 500;