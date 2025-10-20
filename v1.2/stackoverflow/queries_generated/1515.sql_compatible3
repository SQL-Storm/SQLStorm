WITH RECURSIVE RecursiveAnsComplexity AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.Score AS AnswerScore,
        row_number() OVER (PARTITION BY p.ParentId ORDER BY p.CreationDate ASC) AS AnswerRank,
        array_agg(pt.Name) OVER (PARTITION BY p.ParentId) AS ParentPostTypes,
        1 AS Depth
    FROM
        Posts p
        JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE
        p.PostTypeId = 2

    UNION ALL

    SELECT
        r.AnswerId,
        p.ParentId AS QuestionId,
        r.AnswerScore,
        r.AnswerRank,
        r.ParentPostTypes,
        r.Depth + 1
    FROM
        RecursiveAnsComplexity r
        JOIN Posts p ON r.QuestionId = p.Id
    WHERE 
       r.Depth < 3 
       AND p.ParentId IS NOT NULL
), QuestionsScoresFiltered AS (
    SELECT
        pq.Id,
        COALESCE(pq.Score, 0) AS QScore,
        COALESCE(pv.UpVotes,0) AS UpVotesCount,
        COALESCE(pv.DownVotes,0) AS DownVotesCount,
        pq.CreationDate,
        SUBSTRING(COALESCE(pq.Title, ''), 1, 60) AS ShortTitle,
        CASE 
            WHEN pq.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN pq.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            ELSE 'Open' 
        END AS Status,
        pq.Tags,
        array_to_string(
            array(
                SELECT unnest(string_to_array(regexp_replace(COALESCE(pq.Tags, ''), '[\"<>]', '', 'g'), '><')) 
                EXCEPT
                SELECT unnest(array['java', 'sql','database'])
            ), ', '
        ) AS FilteredTags,
        (SELECT count(DISTINCT vh.Id) FROM Votes vh WHERE vh.PostId = pq.Id AND vh.VoteTypeId = 2) AS QuestionUpvotes
    FROM
        Posts pq
    LEFT JOIN (
        SELECT PostId,
               SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) pv ON pv.PostId = pq.Id
    WHERE pq.PostTypeId = 1
), UserBadgesCS_BIT AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount,
        BOOL_OR(CASE WHEN b.TagBased IS NULL THEN false ELSE b.TagBased END) AS HasTagBasedBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
)
SELECT
    qf.Id AS QuestionId,
    qf.QScore,
    qf.UpVotesCount,
    qf.DownVotesCount,
    qf.CreationDate,
    qf.ShortTitle,
    qf.Status,
    qf.Tags,
    qf.FilteredTags,
    qf.QuestionUpvotes,
    ub.UserId,
    ub.DisplayName,
    ub.GoldBadgesCount,
    ub.SilverBadgesCount,
    ub.BronzeBadgesCount,
    ub.HasTagBasedBadges,
    rac.AnswerId,
    rac.AnswerScore,
    rac.AnswerRank,
    rac.ParentPostTypes,
    rac.Depth
FROM QuestionsScoresFiltered qf
LEFT JOIN Posts p_owner ON p_owner.Id = qf.Id
LEFT JOIN UserBadgesCS_BIT ub ON ub.UserId = p_owner.OwnerUserId
LEFT JOIN RecursiveAnsComplexity rac ON rac.QuestionId = qf.Id
GROUP BY
    qf.Id,
    qf.QScore,
    qf.UpVotesCount,
    qf.DownVotesCount,
    qf.CreationDate,
    qf.ShortTitle,
    qf.Status,
    qf.Tags,
    qf.FilteredTags,
    qf.QuestionUpvotes,
    ub.UserId,
    ub.DisplayName,
    ub.GoldBadgesCount,
    ub.SilverBadgesCount,
    ub.BronzeBadgesCount,
    ub.HasTagBasedBadges,
    rac.AnswerId,
    rac.AnswerScore,
    rac.AnswerRank,
    rac.ParentPostTypes,
    rac.Depth
ORDER BY qf.CreationDate DESC, qf.Id;