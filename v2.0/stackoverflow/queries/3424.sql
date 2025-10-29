WITH
    RecentComments AS (
        SELECT
            c.PostId,
            c.Id AS CommentId,
            c.Text,
            c.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn
        FROM Comments c
    ),
    UserBadgeCounts AS (
        SELECT
            b.UserId,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
            COUNT(*)                                       AS TotalBadges
        FROM Badges b
        GROUP BY b.UserId
    ),
    UserPostStats AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)                      AS QuestionCount,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)                      AS AnswerCount,
            AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END)                  AS AvgQuestionScore,
            AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END)                  AS AvgAnswerScore,
            SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END)       AS TotalQuestionViews
        FROM Posts p
        GROUP BY p.OwnerUserId
    ),
    UserVoteStats AS (
        SELECT
            v.UserId,
            COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesCast,
            COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesCast,
            COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesCast
        FROM Votes v
        WHERE v.UserId IS NOT NULL
        GROUP BY v.UserId
    ),
    RecentQuestionComments AS (
        SELECT rc_inner.PostId, rc_inner.Text, rc_inner.CreationDate
        FROM RecentComments rc_inner
        WHERE rc_inner.rn = 1
    ),
    CombinedStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(bc.GoldBadges,   0) AS GoldBadges,
            COALESCE(bc.SilverBadges, 0) AS SilverBadges,
            COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
            COALESCE(ps.QuestionCount, 0)           AS QuestionCount,
            COALESCE(ps.AnswerCount,   0)           AS AnswerCount,
            COALESCE(ps.AvgQuestionScore, 0)        AS AvgQuestionScore,
            COALESCE(ps.AvgAnswerScore,   0)        AS AvgAnswerScore,
            COALESCE(vs.UpVotesCast,   0)           AS UpVotesCast,
            COALESCE(vs.DownVotesCast, 0)           AS DownVotesCast,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS ReputationRank,
            CASE
                WHEN u.Reputation >= 20000 THEN 'Legendary'
                WHEN u.Reputation >= 10000 THEN 'Expert'
                WHEN u.Reputation >=  5000 THEN 'Contributor'
                ELSE                                 'Newbie'
            END AS ReputationTier,
            rqc.Text        AS LatestQuestionComment,
            rqc.CreationDate AS LatestQuestionCommentDate
        FROM Users u
        LEFT JOIN UserBadgeCounts bc ON bc.UserId = u.Id
        LEFT JOIN UserPostStats   ps ON ps.UserId = u.Id
        LEFT JOIN UserVoteStats   vs ON vs.UserId = u.Id
        LEFT JOIN RecentQuestionComments rqc
            ON rqc.PostId = (
                SELECT p.Id
                FROM Posts p
                WHERE p.OwnerUserId = u.Id
                  AND p.PostTypeId = 1
                ORDER BY p.Id
                LIMIT 1
            )
    ),
    TopUsers AS (
        SELECT *
        FROM CombinedStats
        WHERE ReputationRank <= 100
    )
SELECT
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.ReputationTier,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.QuestionCount,
    tu.AnswerCount,
    ROUND(tu.AvgQuestionScore, 2) AS AvgQuestionScore,
    ROUND(tu.AvgAnswerScore,   2) AS AvgAnswerScore,
    tu.UpVotesCast,
    tu.DownVotesCast,
    COALESCE(tu.LatestQuestionComment, '<no comments>') AS LatestCommentSnippet,
    CASE
        WHEN tu.LatestQuestionComment IS NULL THEN NULL
        ELSE SUBSTR(tu.LatestQuestionComment, 1, 80) ||
             CASE WHEN LENGTH(tu.LatestQuestionComment) > 80 THEN '...' ELSE '' END
    END AS CommentPreview,
    tu.ReputationRank
FROM TopUsers tu

UNION ALL

SELECT
    -1                                          AS Id,
    'Anonymous'                                 AS DisplayName,
    0                                           AS Reputation,
    'Newbie'                                    AS ReputationTier,
    0                                           AS GoldBadges,
    0                                           AS SilverBadges,
    0                                           AS BronzeBadges,
    0                                           AS QuestionCount,
    0                                           AS AnswerCount,
    0.00                                        AS AvgQuestionScore,
    0.00                                        AS AvgAnswerScore,
    0                                           AS UpVotesCast,
    0                                           AS DownVotesCast,
    '<no comments>'                             AS LatestCommentSnippet,
    NULL                                        AS CommentPreview,
    NULL                                        AS ReputationRank

ORDER BY ReputationRank NULLS LAST, Id;