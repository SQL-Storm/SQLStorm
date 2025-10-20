SELECT
    p1.Id AS QuestionId,
    p1.Title AS QuestionTitle,
    p1.CreationDate AS QuestionCreationDate,
    p1.Score AS QuestionScore,
    p1.ViewCount AS QuestionViewCount,
    array_length(string_to_array(substring(p1.Tags FROM 2 FOR (LENGTH(p1.Tags)-2)), '><'), 1) AS NumberOfTags,
    COALESCE(acceptableAnswer.AnswerId, -1) AS AcceptedAnswerId,
    acceptableAnswer.CreationDate AS AnswerCreationDate,
    acceptableAnswer.Score AS AnswerScore,
    totalAnswers.AnswerCount,
    totalComments.CommentCount AS QuestionComments,
    totalVotes.UpVotes AS TotalUpVotes,
    totalVotes.DownVotes AS TotalDownVotes,
    totalTags.TotalTagRevisions,
    badge_summary.BadgeCount,
    user_reputation.Reputation AS QuestionOwnerReputation
FROM
    Posts p1
LEFT JOIN (
    SELECT
        a_parent.Id AS AnswerId,
        a_parent.CreationDate,
        a_parent.Score,
        a_parent.ParentId
    FROM Posts a_parent
    WHERE a_parent.PostTypeId = 2
      AND a_parent.CreationDate = (
        SELECT MAX(a2.CreationDate)
        FROM Posts a2
        WHERE a2.ParentId = a_parent.ParentId
          AND a2.PostTypeId = 2
      )
) AS acceptableAnswer ON acceptableAnswer.ParentId = p1.Id
LEFT JOIN (
    SELECT
        a.ParentId,
        COUNT(*) AS AnswerCount
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
) AS totalAnswers ON totalAnswers.ParentId = p1.Id
LEFT JOIN (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount
    FROM Comments c
    GROUP BY c.PostId
) AS totalComments ON totalComments.PostId = p1.Id
LEFT JOIN (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    GROUP BY v.PostId
) AS totalVotes ON totalVotes.PostId = p1.Id
LEFT JOIN (
    SELECT
        ph.PostId,
        COUNT(*) AS TotalTagRevisions
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 6)
    GROUP BY ph.PostId
) AS totalTags ON totalTags.PostId = p1.Id
LEFT JOIN (
    SELECT
        b.UserId,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId
) AS badge_summary ON badge_summary.UserId = p1.OwnerUserId
LEFT JOIN (
    SELECT
        u.Id,
        u.Reputation
    FROM Users u
) AS user_reputation ON user_reputation.Id = p1.OwnerUserId
WHERE p1.PostTypeId = 1
ORDER BY p1.CreationDate DESC
LIMIT 10;