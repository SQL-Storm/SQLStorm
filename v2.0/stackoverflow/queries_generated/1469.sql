-- {"query": "1469.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4084} 

WITH UserMeta AS (
    SELECT
        u.Id AS UserId,
        COALESCE(u.DisplayName, 'Anonymous User') AS DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / (3600 * 24 * 365.25) AS AccountAgeYears,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        CASE
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 2500 THEN 'Senior'
            WHEN u.Reputation >= 500 THEN 'Mid-Tier'
            ELSE 'Novice'
        END AS ReputationTier,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        u.LastAccessDate
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes, u.Location, u.LastAccessDate
),
PostActivitySummary AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        COALESCE(p.AnswerCount, 0) AS PostAnswerCount,
        COALESCE(p.CommentCount, 0) AS PostCommentCount,
        COALESCE(p.FavoriteCount, 0) AS PostFavoriteCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ClosedDate,
        p.LastEditDate,
        p.LastActivityDate,
        (SELECT COUNT(DISTINCT ph.Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS TotalEdits,
        (SELECT COALESCE(SUM(c.Score), 0) FROM Comments c WHERE c.PostId = p.Id) AS TotalCommentScore,
        (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotesReceived,
        (SELECT COUNT(v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotesReceived,
        CASE
            WHEN p.Body LIKE '%<pre><code>%' AND p.Body LIKE '%</pre></code>%' THEN 'ContainsCodeBlock'
            WHEN p.Body LIKE '%http%' OR p.Body LIKE '%https%' THEN 'ContainsLink'
            WHEN p.Body IS NULL OR LENGTH(TRIM(p.Body)) = 0 THEN 'EmptyBody'
            ELSE 'TextOnly'
        END AS BodyContentCategory,
        NULLIF(p.ViewCount, 0) AS ViewCountNonNull
    FROM
        Posts p
    WHERE
        p.PostTypeId IN (1, 2) -- Questions or Answers
),
PostHistoryTimeline AS (
    SELECT
        ph.Id AS HistoryId,
        ph.PostId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC, ph.Id ASC) AS HistoryRank,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC, ph.Id ASC) AS PrevHistoryDate,
        LEAD(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC, ph.Id ASC) AS NextHistoryDate,
        ph.UserId AS HistoryUserId,
        ph.Comment AS HistoryComment,
        ph.Text AS HistoryText
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11) -- Initial, Edit, Close, Reopen
)
SELECT
    um.UserId,
    um.DisplayName,
    um.Reputation,
    um.ReputationTier,
    um.AccountAgeYears,
    um.UserProfileViews,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    pas.PostId,
    pas.PostTypeId,
    pas.Title,
    pas.PostScore,
    pas.PostViewCount,
    pas.PostAnswerCount,
    pas.PostCommentCount,
    pas.PostFavoriteCount,
    pas.UpVotesReceived,
    pas.DownVotesReceived,
    pas.TotalEdits,
    pas.TotalCommentScore,
    pas.BodyContentCategory,
    pas.PostCreationDate,
    pas.ClosedDate,
    ph_first.HistoryDate AS InitialPostDate,
    ph_last_edit.HistoryDate AS LastEditHistoryDate,
    EXTRACT(EPOCH FROM (COALESCE(ph_last_edit.HistoryDate, pas.PostCreationDate) - pas.PostCreationDate)) / (3600 * 24) AS DaysUntilFirstEdit,
    COALESCE(ph_closed.HistoryComment, 'N/A') AS CloseReasonIdComment,
    COALESCE(crt.Name, 'Not Closed') AS CloseReasonName,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    CASE
        WHEN pas.AcceptedAnswerId IS NOT NULL THEN 'Answered'
        WHEN pas.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN pas.PostAnswerCount = 0 AND pas.PostViewCount > 500 AND pas.PostCreationDate < CURRENT_TIMESTAMP - INTERVAL '6 months' THEN 'UnansweredPopularOld'
        WHEN pas.PostAnswerCount = 0 AND pas.PostViewCount > 100 THEN 'UnansweredPopularRecent'
        ELSE 'Open'
    END AS PostStatus,
    (pas.PostScore * 2.5 + pas.PostFavoriteCount * 3.0 + pas.PostAnswerCount * 5.0 + pas.TotalEdits * 0.5) / (COALESCE(pas.ViewCountNonNull, 1.0) + 1.0) AS EngagementRatio,
    (SELECT AVG(p_corr.Score)
     FROM Posts p_corr
     WHERE p_corr.OwnerUserId = um.UserId
       AND p_corr.PostTypeId = 1
       AND p_corr.CreationDate < pas.PostCreationDate
       AND p_corr.Score > (pas.PostScore / 2.0)
       AND p_corr.Id != pas.PostId
    ) AS AvgScoreOfPreviousSimilarPosts,
    RANK() OVER (PARTITION BY um.ReputationTier ORDER BY pas.PostScore DESC, pas.PostViewCount DESC) AS RankWithinTier,
    NTILE(5) OVER (ORDER BY pas.PostViewCount DESC, pas.PostScore DESC) AS ViewCountQuintile,
    AVG(pas.PostScore) OVER (PARTITION BY um.ReputationTier) AS AvgScoreForTier,
    SUM(pas.PostCommentCount) OVER (PARTITION BY um.UserId ORDER BY pas.PostCreationDate ASC) AS CumulativeUserComments,
    COALESCE(
        (SELECT AVG(EXTRACT(EPOCH FROM (ph_inner.NextHistoryDate - ph_inner.HistoryDate))) / (3600 * 24)
         FROM PostHistoryTimeline ph_inner
         WHERE ph_inner.PostId = pas.PostId
           AND ph_inner.PostHistoryTypeId IN (4, 5, 6)
           AND ph_inner.NextHistoryDate IS NOT NULL
        ), 0.0) AS AvgEditIntervalDays,
    LOWER(SUBSTRING(COALESCE(pas.Title, 'No Title Provided'), 1, 75)) AS LowercasedTitleSnippet,
    CASE
        WHEN pas.Tags IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(string_to_array(SUBSTRING(pas.Tags, 2, LENGTH(pas.Tags)-2), '><')) AS tag WHERE tag ILIKE '%sql%' OR tag ILIKE '%database%' OR tag ILIKE '%performance%') THEN TRUE
        ELSE FALSE
    END AS ContainsRelevantTag,
    pas.PostScore - COALESCE(pas.UpVotesReceived, 0) + COALESCE(pas.DownVotesReceived, 0) AS ScoreDeltaFromVoteType,
    CASE
        WHEN um.UserLocation ILIKE '%London%' OR um.UserLocation ILIKE '%New York%' OR um.UserLocation ILIKE '%NYC%' THEN 'MajorCity'
        WHEN um.UserLocation = 'Unknown' THEN 'LocationUnknown'
        ELSE 'OtherRegion'
    END AS UserLocationCategory
FROM
    UserMeta um
JOIN
    PostActivitySummary pas ON um.UserId = pas.OwnerUserId
LEFT JOIN LATERAL
    (SELECT pht.HistoryDate FROM PostHistoryTimeline pht WHERE pht.PostId = pas.PostId AND pht.PostHistoryTypeId IN (1,2,3) ORDER BY pht.HistoryDate ASC LIMIT 1) AS ph_first ON TRUE
LEFT JOIN LATERAL
    (SELECT pht.HistoryDate FROM PostHistoryTimeline pht WHERE pht.PostId = pas.PostId AND pht.PostHistoryTypeId IN (4,5,6) ORDER BY pht.HistoryDate DESC LIMIT 1) AS ph_last_edit ON TRUE
LEFT JOIN LATERAL
    (SELECT pht.HistoryComment FROM PostHistoryTimeline pht WHERE pht.PostId = pas.PostId AND pht.PostHistoryTypeId = 10 ORDER BY pht.HistoryDate DESC LIMIT 1) AS ph_closed ON TRUE
LEFT JOIN
    CloseReasonTypes crt ON (ph_closed.HistoryComment ~ '^[0-9]+$' AND crt.Id = CAST(ph_closed.HistoryComment AS smallint))
LEFT JOIN
    PostLinks pl ON pas.PostId = pl.PostId AND pl.LinkTypeId = 3 -- Only duplicate links
LEFT JOIN
    LinkTypes lt ON pl.LinkTypeId = lt.Id
WHERE
    pas.PostTypeId = 1 -- Only Questions for this part of the UNION
    AND pas.PostScore >= -5 -- Filter out excessively downvoted posts
    AND um.AccountAgeYears > 0.25 -- Filter out very new users for meaningful analytics
    AND (pas.LastEditDate IS NOT NULL OR pas.PostCreationDate > CURRENT_TIMESTAMP - INTERVAL '18 months') -- Posts that have been edited or are relatively recent
    AND NOT EXISTS (
        SELECT 1 FROM PostHistory ph_del
        WHERE ph_del.PostId = pas.PostId
        AND ph_del.PostHistoryTypeId = 12 -- Post Deleted
        AND ph_del.CreationDate > pas.PostCreationDate
    )

UNION ALL

-- Second part of the UNION: Analyze Answers (PostTypeId = 2) with different metrics and filters
SELECT
    um.UserId,
    um.DisplayName,
    um.Reputation,
    um.ReputationTier,
    um.AccountAgeYears,
    um.UserProfileViews,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    pas.PostId,
    pas.PostTypeId,
    NULL AS Title, -- Answers don't have titles in the Posts table
    pas.PostScore,
    pas.PostViewCount, -- ViewCount is always 0 for answers, but kept for schema consistency
    NULL AS PostAnswerCount, -- Answers do not have AnswerCount
    pas.PostCommentCount,
    pas.PostFavoriteCount,
    pas.UpVotesReceived,
    pas.DownVotesReceived,
    pas.TotalEdits,
    pas.TotalCommentScore,
    pas.BodyContentCategory,
    pas.PostCreationDate,
    NULL AS ClosedDate, -- Answers cannot be closed directly, only their parent question
    ph_first.HistoryDate AS InitialPostDate,
    ph_last_edit.HistoryDate AS LastEditHistoryDate,
    EXTRACT(EPOCH FROM (COALESCE(ph_last_edit.HistoryDate, pas.PostCreationDate) - pas.PostCreationDate)) / (3600 * 24) AS DaysUntilFirstEdit,
    NULL AS CloseReasonIdComment, -- N/A for answers
    NULL AS CloseReasonName, -- N/A for answers
    pl.RelatedPostId, -- Can represent a link to other related questions/answers
    lt.Name AS LinkTypeName,
    CASE
        WHEN EXISTS (SELECT 1 FROM Posts q WHERE q.Id = pas.ParentId AND q.AcceptedAnswerId = pas.PostId) THEN 'AcceptedAnswer'
        WHEN pas.PostScore >= 20 THEN 'HighlyScoredAnswer'
        WHEN pas.PostScore >= 5 AND pas.PostCreationDate > CURRENT_TIMESTAMP - INTERVAL '6 months' THEN 'RecentlyGoodAnswer'
        ELSE 'NormalAnswer'
    END AS PostStatus,
    (pas.PostScore * 4.0 + pas.PostFavoriteCount * 2.0 + pas.TotalEdits * 0.8 + pas.TotalCommentScore * 0.5) / (1.0 + EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - pas.PostCreationDate)) / (3600 * 24 * 30)) AS AnswerEffectivenessScore,
    (SELECT AVG(p_corr_ans.Score)
     FROM Posts p_corr_ans
     WHERE p_corr_ans.OwnerUserId = um.UserId
       AND p_corr_ans.PostTypeId = 2
       AND p_corr_ans.CreationDate < pas.PostCreationDate
       AND p_corr_ans.Score > (pas.PostScore * 0.75)
       AND p_corr_ans.Id != pas.PostId
    ) AS AvgScoreOfPreviousSimilarPosts, -- Correlated subquery for answers
    RANK() OVER (PARTITION BY um.ReputationTier ORDER BY pas.PostScore DESC, pas.TotalEdits DESC) AS RankWithinTier,
    NTILE(5) OVER (ORDER BY pas.PostScore DESC, pas.PostCreationDate ASC) AS AnswerScoreQuintile,
    AVG(pas.PostScore) OVER (PARTITION BY um.ReputationTier) AS AvgScoreForTier,
    SUM(pas.PostCommentCount) OVER (PARTITION BY um.UserId ORDER BY pas.PostCreationDate ASC) AS CumulativeUserComments,
    COALESCE(
        (SELECT AVG(EXTRACT(EPOCH FROM (ph_inner.NextHistoryDate - ph_inner.HistoryDate))) / (3600 * 24)
         FROM PostHistoryTimeline ph_inner
         WHERE ph_inner.PostId = pas.PostId
           AND ph_inner.PostHistoryTypeId IN (4, 5, 6)
           AND ph_inner.NextHistoryDate IS NOT NULL
        ), 0.0) AS AvgEditIntervalDays,
    LOWER(SUBSTRING(COALESCE(pas.Body, 'No Body Provided'), 1, 75)) AS LowercasedBodySnippet, -- Using Body for answers, not Title
    CASE
        WHEN pas.BodyContentCategory = 'ContainsCodeBlock' THEN TRUE
        ELSE FALSE
    END AS ContainsCodeInAnswer,
    pas.PostScore - COALESCE(pas.UpVotesReceived, 0) + COALESCE(pas.DownVotesReceived, 0) AS ScoreDeltaFromVoteType,
    CASE
        WHEN um.UserLocation ILIKE '%London%' OR um.UserLocation ILIKE '%New York%' OR um.UserLocation ILIKE '%NYC%' THEN 'MajorCity'
        WHEN um.UserLocation = 'Unknown' THEN 'LocationUnknown'
        ELSE 'OtherRegion'
    END AS UserLocationCategory
FROM
    UserMeta um
JOIN
    PostActivitySummary pas ON um.UserId = pas.OwnerUserId
LEFT JOIN LATERAL
    (SELECT pht.HistoryDate FROM PostHistoryTimeline pht WHERE pht.PostId = pas.PostId AND pht.PostHistoryTypeId IN (1,2,3) ORDER BY pht.HistoryDate ASC LIMIT 1) AS ph_first ON TRUE
LEFT JOIN LATERAL
    (SELECT pht.HistoryDate FROM PostHistoryTimeline pht WHERE pht.PostId = pas.PostId AND pht.PostHistoryTypeId IN (4,5,6) ORDER BY pht.HistoryDate DESC LIMIT 1) AS ph_last_edit ON TRUE
LEFT JOIN
    PostLinks pl ON pas.PostId = pl.RelatedPostId AND pl.LinkTypeId = 1 -- Answers might be linked from other posts
LEFT JOIN
    LinkTypes lt ON pl.LinkTypeId = lt.Id
WHERE
    pas.PostTypeId = 2 -- Only Answers for this part of the UNION
    AND pas.PostScore >= 0 -- Only non-negative score answers
    AND um.AccountAgeYears > 0.25
    AND (pas.LastEditDate IS NOT NULL OR pas.PostCreationDate > CURRENT_TIMESTAMP - INTERVAL '18 months');
