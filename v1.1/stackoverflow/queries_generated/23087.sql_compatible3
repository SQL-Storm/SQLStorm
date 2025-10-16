WITH ActivePosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS ScoreRank,
        STRING_AGG(t.tag_val, ', ') AS PostTags
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags) - 2)), '><')) AS tag_val
    ) t
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate, p.AnswerCount
    HAVING COUNT(t.tag_val) > 1
),
UserEdits AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS EditCount,
        AVG(CASE WHEN ph.Comment IS NULL THEN 0 ELSE LENGTH(ph.Comment) END) AS AvgCommentLength
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) AND ph.CreationDate > DATE '2020-01-01'
    GROUP BY ph.UserId
),
TopBadges AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Badges b
    GROUP BY b.UserId
    HAVING SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) > 0
),
VoteAnalysis AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    GROUP BY v.PostId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(ue.EditCount, 0) AS EditCount,
    COALESCE(ue.AvgCommentLength, 0) AS AvgCommentLength,
    tb.GoldBadges,
    tb.SilverBadges,
    ap.PostId,
    ap.Score,
    ap.ViewCount,
    ap.AnswerCount,
    ap.ScoreRank,
    ap.PostTags,
    va.UpVotes,
    va.DownVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ap.PostId AND c.Score > 0) AS PositiveComments,
    CASE 
        WHEN ap.Score > 0 AND COALESCE(va.UpVotes,0) > COALESCE(va.DownVotes,0) THEN 'Popular'
        WHEN ap.Score < 0 OR COALESCE(va.UpVotes,0) <= COALESCE(va.DownVotes,0) THEN 'Controversial'
        ELSE 'Neutral'
    END AS PostStatus,
    LAG(ap.Score) OVER (PARTITION BY u.Id ORDER BY ap.CreationDate) AS PreviousScore
FROM Users u
LEFT JOIN TopBadges tb ON tb.UserId = u.Id
LEFT JOIN UserEdits ue ON ue.UserId = u.Id
INNER JOIN ActivePosts ap ON ap.OwnerUserId = u.Id
LEFT JOIN VoteAnalysis va ON va.PostId = ap.PostId
WHERE u.Reputation > 1000
  AND EXISTS (
      SELECT 1 FROM PostLinks pl 
      WHERE pl.PostId = ap.PostId AND pl.LinkTypeId = 3
  )
  AND ap.ScoreRank <= 5
UNION
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(ue.EditCount, 0) AS EditCount,
    COALESCE(ue.AvgCommentLength, 0) AS AvgCommentLength,
    tb.GoldBadges,
    tb.SilverBadges,
    NULL AS PostId,
    NULL AS Score,
    NULL AS ViewCount,
    NULL AS AnswerCount,
    NULL AS ScoreRank,
    NULL AS PostTags,
    NULL AS UpVotes,
    NULL AS DownVotes,
    NULL AS PositiveComments,
    'No Posts' AS PostStatus,
    NULL AS PreviousScore
FROM Users u
LEFT JOIN TopBadges tb ON tb.UserId = u.Id
LEFT JOIN UserEdits ue ON ue.UserId = u.Id
WHERE u.Reputation > 1000
  AND NOT EXISTS (
      SELECT 1 FROM ActivePosts ap2 WHERE ap2.OwnerUserId = u.Id
  )
ORDER BY UserId, ScoreRank;