WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyAmount,
        MAX(p.LastActivityDate) AS LastActivityDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
),
TagActivity AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        SUM(p.ViewCount) AS TotalViews,
        SUM(p.AnswerCount) AS TotalAnswers,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        COALESCE(MAX(p.CreationDate), TIMESTAMP '1970-01-01') AS LatestQuestionDate
    FROM
        Tags t
    LEFT JOIN
        Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.Id, t.TagName
),
HighActivityUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        VoteCount,
        TotalBountyAmount,
        LastActivityDate,
        ROW_NUMBER() OVER (ORDER BY (PostCount + CommentCount + VoteCount) DESC) AS ActivityRank
    FROM
        UserActivity
),
PopularTags AS (
    SELECT
        TagId,
        TagName,
        QuestionCount,
        TotalViews,
        TotalAnswers,
        TotalUpvotes,
        TotalDownvotes,
        LatestQuestionDate,
        ROW_NUMBER() OVER (ORDER BY (QuestionCount + TotalUpvotes) DESC) AS PopularityRank
    FROM
        TagActivity
)
SELECT
    h.UserId,
    h.DisplayName,
    h.Reputation,
    h.PostCount,
    h.CommentCount,
    h.VoteCount,
    h.TotalBountyAmount,
    h.LastActivityDate,
    h.ActivityRank,
    p.TagId,
    p.TagName,
    p.QuestionCount,
    p.TotalViews,
    p.TotalAnswers,
    p.TotalUpvotes,
    p.TotalDownvotes,
    p.LatestQuestionDate,
    p.PopularityRank,
    COALESCE(
      (SELECT MAX(ph.CreationDate)
       FROM PostHistory ph
       WHERE ph.PostId IN (SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = h.UserId)
         AND ph.PostHistoryTypeId IN (4, 5)
      ), TIMESTAMP '1970-01-01') AS LastEditDate,
    COALESCE(
      (SELECT MAX(v2.CreationDate)
       FROM Votes v2
       WHERE v2.UserId = h.UserId
         AND v2.VoteTypeId IN (2, 3, 8)
      ), TIMESTAMP '1970-01-01') AS LastVoteDate
FROM
    HighActivityUsers h
JOIN
    PopularTags p ON h.ActivityRank = p.PopularityRank
WHERE
    h.ActivityRank <= 100
    AND p.PopularityRank <= 100
ORDER BY
    h.ActivityRank, p.PopularityRank;