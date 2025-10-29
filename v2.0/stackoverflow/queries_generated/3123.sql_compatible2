WITH
    ranked_posts AS (
        SELECT
            p.OwnerUserId AS UserId,
            p.Id AS PostId,
            p.Score,
            p.CreationDate,
            ROW_NUMBER() OVER (
                PARTITION BY p.OwnerUserId
                ORDER BY p.Score DESC, p.CreationDate DESC
            ) AS rn,
            CASE
                WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1
                ELSE 0
            END AS IsQuestionWithAccepted
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
    ),
    user_post_agg AS (
        SELECT
            up.UserId,
            COUNT(CASE WHEN up.PostTypeId = 1 THEN 1 END) AS QuestionCount,
            COUNT(CASE WHEN up.PostTypeId = 2 THEN 1 END) AS AnswerCount,
            COUNT(CASE WHEN up.Score >= 10 THEN 1 END) AS HighScorePostCount,
            SUM(up.Score) AS TotalScore,
            MAX(up.CreationDate) AS LastPostDate,
            SUM(up.IsQuestionWithAccepted) AS AcceptedAnswerCount
        FROM (
            SELECT
                p.OwnerUserId AS UserId,
                p.PostTypeId,
                p.Score,
                p.CreationDate,
                CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS IsQuestionWithAccepted
            FROM Posts p
            WHERE p.OwnerUserId IS NOT NULL
        ) up
        GROUP BY up.UserId
    ),
    badge_counts AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount,
            COUNT(*) AS TotalBadgeCount
        FROM Badges b
        GROUP BY b.UserId
    ),
    recent_activity AS (
        SELECT
            u.Id AS UserId,
            COALESCE(v.vote_cnt, 0) AS RecentVoteCount,
            COALESCE(c.comment_cnt, 0) AS RecentCommentCount,
            GREATEST(
                COALESCE(v.last_vote_date, TIMESTAMP '1970-01-01'),
                COALESCE(c.last_comment_date, TIMESTAMP '1970-01-01')
            ) AS LastActivityDate
        FROM Users u
        LEFT JOIN (
            SELECT
                v.UserId,
                COUNT(*) AS vote_cnt,
                MAX(v.CreationDate) AS last_vote_date
            FROM Votes v
            WHERE v.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
            GROUP BY v.UserId
        ) v ON v.UserId = u.Id
        LEFT JOIN (
            SELECT
                c.UserId,
                COUNT(*) AS comment_cnt,
                MAX(c.CreationDate) AS last_comment_date
            FROM Comments c
            WHERE c.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
            GROUP BY c.UserId
        ) c ON c.UserId = u.Id
    ),
    tag_usage AS (
        SELECT
            p.OwnerUserId AS UserId,
            LOWER(TRIM(t)) AS Tag,
            COUNT(*) AS TagCount
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT UNNEST(STRING_TO_ARRAY(
                REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' '
            )) AS t
        ) taglist
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, LOWER(TRIM(t))
    ),
    top_tags AS (
        SELECT
            tu.UserId,
            tu.Tag,
            tu.TagCount,
            ROW_NUMBER() OVER (PARTITION BY tu.UserId ORDER BY tu.TagCount DESC, tu.Tag) AS tag_rank
        FROM tag_usage tu
    ),
    user_top_tags AS (
        SELECT
            UserId,
            STRING_AGG(Tag, ', ') FILTER (WHERE tag_rank <= 3) AS Top3Tags
        FROM top_tags
        GROUP BY UserId
    ),
    detailed_users AS (
        SELECT
            u.Id AS UserId,
            COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
            u.Reputation,
            COALESCE(upa.QuestionCount, 0) AS QuestionCount,
            COALESCE(upa.AnswerCount, 0) AS AnswerCount,
            COALESCE(upa.HighScorePostCount, 0) AS HighScorePostCount,
            COALESCE(upa.TotalScore, 0) AS TotalScore,
            COALESCE(upa.AcceptedAnswerCount, 0) AS AcceptedAnswerCount,
            COALESCE(bc.GoldBadgeCount, 0) AS GoldBadges,
            COALESCE(bc.SilverBadgeCount, 0) AS SilverBadges,
            COALESCE(bc.BronzeBadgeCount, 0) AS BronzeBadges,
            COALESCE(bc.TotalBadgeCount, 0) AS TotalBadges,
            ra.RecentVoteCount,
            ra.RecentCommentCount,
            ra.LastActivityDate,
            COALESCE(utt.Top3Tags, '') AS Top3Tags,
            CASE
                WHEN u.CreationDate < (CAST('2024-10-01' AS date) - INTERVAL '5' YEAR) THEN 'Veteran'
                WHEN u.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1' YEAR) THEN 'Newcomer'
                ELSE 'Established'
            END AS UserEra,
            (COALESCE(upa.TotalScore, 0) * 0.6
             + COALESCE(bc.TotalBadgeCount, 0) * 2
             + ra.RecentVoteCount * 0.5
             + ra.RecentCommentCount * 0.3
             + COALESCE(upa.HighScorePostCount, 0) * 1.5
            ) AS CompositeScore
        FROM Users u
        LEFT JOIN user_post_agg upa ON upa.UserId = u.Id
        LEFT JOIN badge_counts bc ON bc.UserId = u.Id
        LEFT JOIN recent_activity ra ON ra.UserId = u.Id
        LEFT JOIN user_top_tags utt ON utt.UserId = u.Id
        WHERE u.Reputation > 1000
    ),
    summary_row AS (
        SELECT
            CAST(NULL AS BIGINT) AS UserId,
            '--- Summary ---' AS DisplayName,
            CAST(NULL AS INT) AS Reputation,
            SUM(QuestionCount) AS QuestionCount,
            SUM(AnswerCount) AS AnswerCount,
            SUM(HighScorePostCount) AS HighScorePostCount,
            SUM(TotalScore) AS TotalScore,
            SUM(AcceptedAnswerCount) AS AcceptedAnswerCount,
            SUM(GoldBadges) AS GoldBadges,
            SUM(SilverBadges) AS SilverBadges,
            SUM(BronzeBadges) AS BronzeBadges,
            SUM(TotalBadges) AS TotalBadges,
            SUM(RecentVoteCount) AS RecentVoteCount,
            SUM(RecentCommentCount) AS RecentCommentCount,
            MAX(LastActivityDate) AS LastActivityDate,
            CAST(NULL AS TEXT) AS Top3Tags,
            CAST(NULL AS TEXT) AS UserEra,
            CAST(NULL AS NUMERIC) AS CompositeScore
        FROM detailed_users
    )
SELECT *
FROM (
    SELECT * FROM detailed_users
    ORDER BY CompositeScore DESC
    LIMIT 100
) t
UNION ALL
SELECT * FROM summary_row;