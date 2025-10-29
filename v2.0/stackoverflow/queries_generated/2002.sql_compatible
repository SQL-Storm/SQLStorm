WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName AS OwnerName,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_score_view,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS total_posts_type
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1,2)
      AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
), HighScoreQuestions AS (
    SELECT
        rp.*,
        (SELECT COUNT(DISTINCT ph.UserId)
         FROM PostHistory ph
         WHERE ph.PostId = rp.Id
           AND ph.PostHistoryTypeId IN (4,5,6)
           AND ph.UserId IS NOT NULL) AS distinct_editors,
        (SELECT COUNT(*)
         FROM Comments c
         WHERE c.PostId = rp.Id
           AND c.CreationDate > rp.CreationDate
           AND (c.Text ILIKE '%bug%' OR c.Text ILIKE '%error%' OR c.Text ILIKE '%issue%' OR c.Text ILIKE '%fail%' OR c.Text ILIKE '%suggest%')
        ) AS flagged_comments_count
    FROM RankedPosts rp
    WHERE rp.PostTypeId = 1
      AND rp.rn_score_view <= 50
), JoinedVotes AS (
    SELECT
        v.PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS upvotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS downvotes,
        SUM(CASE WHEN vt.Name = 'BountyClose' THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS total_bounty_close,
        MAX(v.CreationDate) AS last_vote_date
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.PostId IN (SELECT Id FROM HighScoreQuestions)
    GROUP BY v.PostId
), PostWithLinks AS (
    SELECT
        q.Id AS QuestionId,
        ARRAY_AGG(DISTINCT l.RelatedPostId) FILTER (WHERE l.LinkTypeId = 3) AS duplicate_post_ids,
        ARRAY_AGG(DISTINCT l.RelatedPostId) FILTER (WHERE l.LinkTypeId = 1) AS linked_post_ids
    FROM Posts q
    LEFT JOIN PostLinks l ON q.Id = l.PostId
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
), UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges,
        MAX(b.Date) AS last_badge_date
    FROM Badges b
    WHERE b.UserId IN (SELECT OwnerUserId FROM HighScoreQuestions WHERE OwnerUserId IS NOT NULL)
    GROUP BY b.UserId
), ComplexResult AS (
    SELECT
        hq.Id,
        hq.Title,
        hq.OwnerUserId,
        COALESCE(hq.OwnerName, 'Anonymous') AS OwnerName,
        hq.Reputation,
        hq.Score,
        hq.ViewCount,
        hq.AnswerCount,
        hq.FavoriteCount,
        hq.distinct_editors,
        hq.flagged_comments_count,
        COALESCE(vt.upvotes, 0) AS upvotes,
        COALESCE(vt.downvotes, 0) AS downvotes,
        vt.total_bounty_close,
        pl.duplicate_post_ids,
        pl.linked_post_ids,
        COALESCE(ub.gold_badges,0) AS gold_badges,
        COALESCE(ub.silver_badges,0) AS silver_badges,
        COALESCE(ub.bronze_badges,0) AS bronze_badges,
        CASE
            WHEN hq.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN hq.FavoriteCount > 100 THEN 'Highly Favorited'
            WHEN hq.Score >= 50 THEN 'High Score'
            ELSE 'Normal'
        END AS PostStatus,
        CONCAT_WS(' | ',
            hq.Title,
            'Author: ', COALESCE(hq.OwnerName, 'Unknown'),
            'Reputation: ', COALESCE(CAST(hq.Reputation AS text), '0'),
            CASE WHEN COALESCE(ub.gold_badges,0) > 0 THEN FORMAT('%s Gold Badges', ub.gold_badges) ELSE NULL END,
            CASE WHEN COALESCE(ub.silver_badges,0) > 0 THEN FORMAT('%s Silver Badges', ub.silver_badges) ELSE NULL END,
            CASE WHEN COALESCE(ub.bronze_badges,0) > 0 THEN FORMAT('%s Bronze Badges', ub.bronze_badges) ELSE NULL END
        ) AS SummaryString,
        RANK() OVER (PARTITION BY (CASE
                WHEN hq.Reputation < 1000 THEN 'Low'
                WHEN hq.Reputation BETWEEN 1000 AND 10000 THEN 'Medium'
                ELSE 'High'
            END) ORDER BY hq.Score DESC) AS ScoreRankInReputationGroup,
        (SELECT COUNT(*)
         FROM Posts ans
         WHERE ans.PostTypeId = 2
           AND ans.ParentId = hq.Id
           AND ans.Score > hq.Score) AS BetterAnswersCount
    FROM HighScoreQuestions hq
    LEFT JOIN JoinedVotes vt ON hq.Id = vt.PostId
    LEFT JOIN PostWithLinks pl ON hq.Id = pl.QuestionId
    LEFT JOIN UserBadgeSummary ub ON hq.OwnerUserId = ub.UserId
)
SELECT
    Id,
    Title,
    OwnerUserId,
    OwnerName,
    Reputation,
    Score,
    ViewCount,
    AnswerCount,
    FavoriteCount,
    distinct_editors,
    flagged_comments_count,
    upvotes,
    downvotes,
    total_bounty_close,
    duplicate_post_ids,
    linked_post_ids,
    gold_badges,
    silver_badges,
    bronze_badges,
    PostStatus,
    SummaryString,
    ScoreRankInReputationGroup,
    BetterAnswersCount
FROM ComplexResult
WHERE (ScoreRankInReputationGroup <= 10 OR PostStatus = 'Closed')
  AND (FavoriteCount > 10 OR distinct_editors > 2 OR flagged_comments_count > 0)
ORDER BY ScoreRankInReputationGroup, Score DESC, FavoriteCount DESC
LIMIT 100;