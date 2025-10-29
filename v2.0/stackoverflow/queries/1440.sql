-- {"query": "1440.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3634}
WITH
    HighImpactQuestions AS (
        SELECT
            p.Id AS QuestionId,
            p.Title AS QuestionTitle,
            p.Body AS QuestionBody,
            p.Tags AS QuestionTags,
            p.CreationDate AS QuestionCreationDate,
            p.Score AS QuestionScore,
            p.ViewCount AS QuestionViewCount,
            p.CommentCount AS QuestionCommentCount,
            p.FavoriteCount AS QuestionFavoriteCount,
            p.OwnerUserId AS QuestionOwnerUserId,
            p.AcceptedAnswerId AS AcceptedAnswerId
        FROM
            Posts AS p
        WHERE
            p.PostTypeId = 1
            AND p.AcceptedAnswerId IS NOT NULL
            AND p.ClosedDate IS NULL
            AND p.Score > 75
            AND p.ViewCount > 3000
            AND (
                p.Tags LIKE '%<java>%'
                OR p.Tags LIKE '%<python>%'
                OR p.Tags LIKE '%<javascript>%'
                OR p.Tags LIKE '%<c#>%<'
                OR p.Tags LIKE '%<sql>%'
            )
    ),
    AcceptedAnswerDetails AS (
        SELECT
            hi.QuestionId,
            hi.QuestionTitle,
            hi.QuestionBody,
            hi.QuestionTags,
            hi.QuestionCreationDate,
            hi.QuestionScore,
            hi.QuestionViewCount,
            hi.QuestionCommentCount,
            hi.QuestionFavoriteCount,
            hi.QuestionOwnerUserId,
            COALESCE(u_q.DisplayName, 'Deleted User') AS QuestionOwnerDisplayName,
            u_q.Reputation AS QuestionOwnerReputation,
            u_q.CreationDate AS QuestionOwnerCreationDate,
            u_q.UpVotes AS QuestionOwnerUpVotes,
            u_q.DownVotes AS QuestionOwnerDownVotes,
            aa.Id AS AnswerId,
            aa.Body AS AnswerBody,
            aa.CreationDate AS AnswerCreationDate,
            aa.Score AS AnswerScore,
            aa.CommentCount AS AnswerCommentCount,
            aa.OwnerUserId AS AnswerOwnerUserId,
            COALESCE(u_a.DisplayName, 'Deleted User') AS AnswerOwnerDisplayName,
            u_a.Reputation AS AnswerOwnerReputation,
            u_a.CreationDate AS AnswerOwnerCreationDate,
            u_a.UpVotes AS AnswerOwnerUpVotes,
            u_a.DownVotes AS AnswerOwnerDownVotes,
            (aa.CreationDate - hi.QuestionCreationDate) AS TimeToAcceptAnswer
        FROM
            HighImpactQuestions AS hi
        INNER JOIN
            Posts AS aa ON hi.AcceptedAnswerId = aa.Id
        LEFT JOIN
            Users AS u_q ON hi.QuestionOwnerUserId = u_q.Id
        LEFT JOIN
            Users AS u_a ON aa.OwnerUserId = u_a.Id
    ),
    PostActivityMetrics AS (
        SELECT
            aad.QuestionId,
            aad.AnswerId,
            COUNT(DISTINCT ph_q.Id) FILTER (WHERE ph_q.PostHistoryTypeId IN (4, 5, 6)) AS QuestionEditCount,
            COUNT(DISTINCT ph_a.Id) FILTER (WHERE ph_a.PostHistoryTypeId IN (4, 5, 6)) AS AnswerEditCount,
            COUNT(DISTINCT c_q.Id) AS QuestionCommentCountActual,
            COUNT(DISTINCT c_a.Id) AS AnswerCommentCountActual,
            SUM(CASE WHEN vt_q.VoteTypeId = 2 THEN 1 ELSE 0 END) AS QuestionUpVotesActual,
            SUM(CASE WHEN vt_q.VoteTypeId = 3 THEN 1 ELSE 0 END) AS QuestionDownVotesActual,
            SUM(CASE WHEN vt_a.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AnswerUpVotesActual,
            SUM(CASE WHEN vt_a.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AnswerDownVotesActual,
            MAX(ph_q.CreationDate) AS LastQuestionEditDate,
            MAX(ph_a.CreationDate) AS LastAnswerEditDate,
            RANK() OVER (PARTITION BY aad.QuestionOwnerUserId ORDER BY aad.QuestionCreationDate) AS QuestionRankByUser,
            RANK() OVER (PARTITION BY aad.AnswerOwnerUserId ORDER BY aad.AnswerCreationDate) AS AnswerRankByUser
        FROM
            AcceptedAnswerDetails AS aad
        LEFT JOIN
            PostHistory AS ph_q ON aad.QuestionId = ph_q.PostId
        LEFT JOIN
            PostHistory AS ph_a ON aad.AnswerId = ph_a.PostId
        LEFT JOIN
            Comments AS c_q ON aad.QuestionId = c_q.PostId
        LEFT JOIN
            Comments AS c_a ON aad.AnswerId = c_a.PostId
        LEFT JOIN
            Votes AS vt_q ON aad.QuestionId = vt_q.PostId
        LEFT JOIN
            Votes AS vt_a ON aad.AnswerId = vt_a.PostId
        GROUP BY
            aad.QuestionId,
            aad.AnswerId,
            aad.QuestionOwnerUserId,
            aad.QuestionCreationDate,
            aad.AnswerOwnerUserId,
            aad.AnswerCreationDate
    ),
    RelatedPostsAndTags AS (
        SELECT
            QuestionId,
            AnswerId,
            (
                SELECT COUNT(DISTINCT pl.RelatedPostId)
                FROM PostLinks AS pl
                WHERE pl.PostId = aad.QuestionId
                  AND pl.LinkTypeId = 3
            ) AS DuplicateQuestionCount,
            (
                SELECT COUNT(DISTINCT pl.RelatedPostId)
                FROM PostLinks AS pl
                WHERE pl.PostId = aad.QuestionId
                  AND pl.LinkTypeId = 1
            ) AS LinkedQuestionCount,
            COALESCE(
                NULLIF(
                    SUBSTRING(aad.QuestionTags FROM POSITION('<' IN aad.QuestionTags) + 1 FOR POSITION('>' IN aad.QuestionTags) - POSITION('<' IN aad.QuestionTags) - 1),
                    ''
                ),
                'untagged'
            ) AS PrimaryTag
        FROM
            AcceptedAnswerDetails AS aad
    ),
    UserBadgeSummary AS (
        SELECT
            UserId,
            COUNT(Id) AS TotalBadges,
            COUNT(Id) FILTER (WHERE Class = 1) AS GoldBadges,
            COUNT(Id) FILTER (WHERE Class = 2) AS SilverBadges,
            COUNT(Id) FILTER (WHERE Class = 3) AS BronzeBadges,
            MAX(Date) AS LastBadgeDate
        FROM
            Badges
        GROUP BY
            UserId
    ),
    QuestionAnswerEngagement AS (
        SELECT
            aad.QuestionId,
            aad.QuestionTitle,
            aad.QuestionBody,
            aad.QuestionTags,
            aad.QuestionCreationDate,
            aad.QuestionScore,
            aad.QuestionViewCount,
            aad.QuestionOwnerUserId,
            aad.QuestionOwnerDisplayName,
            aad.QuestionOwnerReputation,
            aad.AnswerId,
            aad.AnswerBody,
            aad.AnswerCreationDate,
            aad.AnswerScore,
            aad.AnswerOwnerUserId,
            aad.AnswerOwnerDisplayName,
            aad.AnswerOwnerReputation,
            aad.TimeToAcceptAnswer,
            pam.QuestionEditCount,
            pam.AnswerEditCount,
            pam.QuestionCommentCountActual,
            pam.AnswerCommentCountActual,
            pam.QuestionUpVotesActual,
            pam.QuestionDownVotesActual,
            pam.AnswerUpVotesActual,
            pam.AnswerDownVotesActual,
            pam.QuestionRankByUser,
            pam.AnswerRankByUser,
            rpat.DuplicateQuestionCount,
            rpat.LinkedQuestionCount,
            rpat.PrimaryTag,
            COALESCE(ub_q.TotalBadges, 0) AS QuestionOwnerTotalBadges,
            COALESCE(ub_q.GoldBadges, 0) AS QuestionOwnerGoldBadges,
            COALESCE(ub_a.TotalBadges, 0) AS AnswerOwnerTotalBadges,
            COALESCE(ub_a.GoldBadges, 0) AS AnswerOwnerGoldBadges,
            (
                (aad.QuestionScore * 0.4)
                + (aad.QuestionViewCount / 2000.0 * 0.15)
                + (COALESCE(aad.QuestionFavoriteCount, 0) * 1.5)
                + (pam.QuestionUpVotesActual * 0.7)
                + (COALESCE(ub_q.GoldBadges, 0) * 8)
                + (pam.QuestionCommentCountActual * 0.5)
            ) AS QuestionImpactScore,
            LAG(aad.QuestionCreationDate, 1, CAST('1970-01-01' AS timestamp)) OVER (PARTITION BY aad.QuestionOwnerUserId ORDER BY aad.QuestionCreationDate) AS PreviousQuestionDateByOwner,
            LEAD(aad.AnswerCreationDate, 1, CAST('2999-01-01' AS timestamp)) OVER (PARTITION BY aad.AnswerOwnerUserId ORDER BY aad.AnswerCreationDate) AS NextAnswerDateByOwner,
            aad.QuestionFavoriteCount
        FROM
            AcceptedAnswerDetails AS aad
        INNER JOIN
            PostActivityMetrics AS pam ON aad.QuestionId = pam.QuestionId AND aad.AnswerId = pam.AnswerId
        INNER JOIN
            RelatedPostsAndTags AS rpat ON aad.QuestionId = rpat.QuestionId AND aad.AnswerId = rpat.AnswerId
        LEFT JOIN
            UserBadgeSummary AS ub_q ON aad.QuestionOwnerUserId = ub_q.UserId
        LEFT JOIN
            UserBadgeSummary AS ub_a ON aad.AnswerOwnerUserId = ub_a.UserId
    )
SELECT
    qae.QuestionId,
    qae.QuestionTitle,
    qae.QuestionCreationDate,
    qae.QuestionScore,
    qae.QuestionViewCount,
    qae.QuestionOwnerDisplayName,
    qae.QuestionOwnerReputation,
    qae.AnswerId,
    qae.AnswerCreationDate,
    qae.AnswerScore,
    qae.AnswerOwnerDisplayName,
    qae.AnswerOwnerReputation,
    qae.TimeToAcceptAnswer,
    qae.QuestionEditCount,
    qae.AnswerEditCount,
    qae.QuestionCommentCountActual,
    qae.AnswerCommentCountActual,
    qae.DuplicateQuestionCount,
    qae.LinkedQuestionCount,
    qae.PrimaryTag,
    qae.QuestionOwnerTotalBadges,
    qae.AnswerOwnerTotalBadges,
    qae.QuestionImpactScore,
    qae.PreviousQuestionDateByOwner,
    qae.NextAnswerDateByOwner,
    CASE
        WHEN qae.QuestionScore >= 300 AND qae.QuestionFavoriteCount IS NOT NULL AND qae.QuestionFavoriteCount > 30 THEN 'Elite & Treasured Question'
        WHEN qae.QuestionScore >= 150 AND qae.QuestionViewCount > 20000 AND qae.QuestionOwnerReputation > 10000 THEN 'Veteran-Backed Viral Post'
        WHEN qae.AnswerScore > qae.QuestionScore * 1.5 AND qae.TimeToAcceptAnswer < INTERVAL '12 hours' THEN 'Quickly Solved & Highly Rated Answer'
        WHEN POSITION('optimization' IN LOWER(qae.QuestionBody)) > 0 AND POSITION('performance' IN LOWER(qae.AnswerBody)) > 0 THEN 'Performance/Optimization Focus'
        WHEN qae.QuestionOwnerDisplayName = 'Deleted User' OR qae.AnswerOwnerDisplayName = 'Deleted User' THEN 'Community-Maintained Post'
        ELSE 'Standard High-Engagement'
    END AS QuestionCategory,
    ROUND(
        (qae.QuestionImpactScore * 0.6) +
        (qae.AnswerScore * 0.25) +
        (
            CASE
                WHEN qae.TimeToAcceptAnswer < INTERVAL '30 minutes' THEN 150
                WHEN qae.TimeToAcceptAnswer < INTERVAL '6 hours' THEN 100
                WHEN qae.TimeToAcceptAnswer < INTERVAL '24 hours' THEN 50
                WHEN qae.TimeToAcceptAnswer < INTERVAL '3 days' THEN 20
                ELSE 5
            END
        ) -
        (qae.QuestionEditCount * 3.0) -
        (qae.AnswerEditCount * 1.5) +
        (qae.QuestionOwnerGoldBadges * 12) +
        (qae.AnswerOwnerGoldBadges * 10) +
        (qae.LinkedQuestionCount * 10) -
        (qae.DuplicateQuestionCount * 15) +
        (
            CASE
                WHEN (qae.QuestionCreationDate - qae.PreviousQuestionDateByOwner) < INTERVAL '7 days' AND qae.PreviousQuestionDateByOwner != CAST('1970-01-01' AS timestamp) THEN 25
                ELSE 0
            END
        )
    , 0) AS OverallEngagementScore
FROM
    QuestionAnswerEngagement AS qae
WHERE
    qae.QuestionOwnerReputation IS NOT NULL
    AND qae.AnswerOwnerReputation IS NOT NULL
    AND qae.QuestionOwnerReputation > (qae.AnswerOwnerReputation * 0.25)
    AND qae.TimeToAcceptAnswer < INTERVAL '14 days'
    AND LENGTH(qae.QuestionBody) > 150
    AND LENGTH(qae.AnswerBody) > 100
    AND (
        (qae.PrimaryTag = 'java' AND qae.QuestionOwnerTotalBadges > 15 AND qae.AnswerOwnerTotalBadges > 5)
        OR (qae.PrimaryTag = 'python' AND qae.AnswerOwnerReputation > 7500 AND qae.QuestionEditCount < 5)
        OR (qae.PrimaryTag = 'javascript' AND qae.QuestionImpactScore > 300 AND qae.LinkedQuestionCount > 0)
    )
ORDER BY
    OverallEngagementScore DESC,
    qae.QuestionCreationDate DESC
LIMIT 750;