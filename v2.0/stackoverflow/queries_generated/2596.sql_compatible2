WITH RankedPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.PostTypeId,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS OwnerRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS OwnerPostCount,
        CONCAT(
            COALESCE(NULLIF(SUBSTRING(p.Tags FROM 2 FOR (POSITION('><' IN (p.Tags || '><')) - 2)), ''), 'NoTag'),
            ' & ',
            COALESCE(
                NULLIF(
                    SUBSTRING(
                        p.Tags
                        FROM (POSITION('><' IN (p.Tags || '><')) + 2)
                        FOR (
                            POSITION('><' IN (SUBSTRING(p.Tags || '><' FROM POSITION('><' IN (p.Tags || '><')) + 2))) - 2
                        )
                    ),
                    ''
                ),
                'NoTag2'
            )
        ) AS TopTags
    FROM
        Posts p
    WHERE
        p.PostTypeId IN (1,2)
        AND p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years'
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM
        Badges b
    GROUP BY
        b.UserId
),
PostScoresWithVotes AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Score,
        v.VoteTypeId,
        COUNT(*) AS VoteCount
    FROM
        Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE
        v.VoteTypeId IN (2,3)
    GROUP BY
        p.Id, p.PostTypeId, p.Score, v.VoteTypeId
),
AggregatedVotes AS (
    SELECT
        p.Id,
        p.PostTypeId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN v.VoteCount ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN v.VoteCount ELSE 0 END) AS DownVotes
    FROM
        Posts p
        LEFT JOIN PostScoresWithVotes v ON p.Id = v.Id
    GROUP BY
        p.Id, p.PostTypeId
),
PostLinksCount AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateCount
    FROM
        PostLinks pl
    GROUP BY
        pl.PostId
),
UserRecentActivity AS (
    SELECT
        u.Id as UserId,
        MAX(ph.CreationDate) AS LastPostEditDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        LEFT JOIN PostHistory ph ON ph.PostId = p.Id
        LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY
        u.Id
),
QuestionsWithCloseStatus AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.ClosedDate,
        ph.Comment AS CloseReasonId,
        crt.Name AS CloseReason
    FROM
        Posts p
        LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
        LEFT JOIN CloseReasonTypes crt ON CAST(crt.Id AS varchar) = ph.Comment
    WHERE
        p.PostTypeId = 1
),
AnswersAcceptedAndScore AS (
    SELECT
        a.Id,
        a.ParentId AS QuestionId,
        a.Score,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted
    FROM
        Posts a
        JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
    WHERE
        a.PostTypeId = 2
),
AnswerRanking AS (
    SELECT
        a.Id,
        a.QuestionId,
        a.Score,
        a.IsAccepted,
        RANK() OVER (PARTITION BY a.QuestionId ORDER BY a.Score DESC) AS ScoreRank
    FROM
        AnswersAcceptedAndScore a
),
QuestionsTopAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Score AS QuestionScore,
        q.AcceptedAnswerId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.IsAccepted,
        a.ScoreRank
    FROM
        Posts q
        LEFT JOIN AnswerRanking a ON a.QuestionId = q.Id AND a.ScoreRank <= 3
    WHERE
        q.PostTypeId = 1
),
UserReputationWindow AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        SUM(u.Reputation) OVER (ORDER BY u.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumSumReputationDesc,
        COUNT(*) OVER (ORDER BY u.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RankByReputation
    FROM
        Users u
),
CombinedSet AS (
    SELECT
        rp.Id as PostId,
        rp.OwnerUserId,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.TopTags,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ar.UpVotes,
        ar.DownVotes,
        plc.LinkedCount,
        plc.DuplicateCount,
        ura.LastPostEditDate,
        ura.LastCommentDate,
        urw.RankByReputation
    FROM
        RankedPosts rp
        LEFT JOIN UserBadgeCounts ubc ON rp.OwnerUserId = ubc.UserId
        LEFT JOIN AggregatedVotes ar ON rp.Id = ar.Id
        LEFT JOIN PostLinksCount plc ON rp.Id = plc.PostId
        LEFT JOIN UserRecentActivity ura ON rp.OwnerUserId = ura.UserId
        LEFT JOIN UserReputationWindow urw ON rp.OwnerUserId = urw.Id
    WHERE
        rp.OwnerRank = 1
)
SELECT DISTINCT
    cs.PostId,
    cs.Title,
    cs.Score,
    cs.ViewCount,
    COALESCE(cs.TopTags, 'NoTags') AS Tags,
    COALESCE(cs.GoldBadges,0) AS GoldBadges,
    COALESCE(cs.SilverBadges,0) AS SilverBadges,
    COALESCE(cs.BronzeBadges,0) AS BronzeBadges,
    COALESCE(cs.UpVotes,0) AS UpVotes,
    COALESCE(cs.DownVotes,0) AS DownVotes,
    COALESCE(cs.LinkedCount,0) AS LinkedPosts,
    COALESCE(cs.DuplicateCount,0) AS DuplicatePosts,
    cs.LastPostEditDate,
    cs.LastCommentDate,
    cs.RankByReputation,
    qwc.ClosedDate,
    qwc.CloseReason,
    qta.AnswerId,
    qta.AnswerScore,
    qta.IsAccepted,
    qta.ScoreRank,
    CASE 
        WHEN cs.ViewCount > 0 THEN ROUND(CAST(cs.Score AS numeric) / NULLIF(cs.ViewCount,0) * 100.0,2)
        ELSE NULL 
    END AS ScoreToViewRatioPercent,
    CASE
        WHEN cs.UpVotes IS NULL OR cs.DownVotes IS NULL THEN NULL
        ELSE ROUND(CASE WHEN cs.DownVotes = 0 THEN CAST(cs.UpVotes AS numeric) ELSE CAST(cs.UpVotes AS numeric) / cs.DownVotes END, 2)
    END AS UpDownRatio,
    CASE 
        WHEN ubc.GoldBadges IS NULL THEN 'No Gold' 
        WHEN ubc.GoldBadges > 10 THEN 'Elite Gold'
        ELSE 'Regular Gold'
    END AS GoldBadgeCategory
FROM
    CombinedSet cs
    LEFT JOIN QuestionsWithCloseStatus qwc ON cs.PostId = qwc.Id
    LEFT JOIN QuestionsTopAnswers qta ON cs.PostId = qta.QuestionId
    LEFT JOIN UserBadgeCounts ubc ON cs.OwnerUserId = ubc.UserId
WHERE
    (qwc.ClosedDate IS NULL OR qwc.ClosedDate > TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months')
    AND (cs.Score > 10 OR cs.ViewCount > 1000)
ORDER BY
    cs.RankByReputation ASC,
    cs.Score DESC,
    cs.ViewCount DESC
LIMIT 100;