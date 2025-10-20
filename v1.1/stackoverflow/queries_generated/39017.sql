-- {"query": "39017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2429} 

WITH ParsedTags AS (
    SELECT
        p.Id          AS PostId,
        p.OwnerUserId AS OwnerId,
        p.CreationDate,
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )
        ) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
TagMetrics AS (
    SELECT
        pt.Tag,
        COUNT(DISTINCT pt.PostId)         AS QuestionCount,
        AVG(p.ViewCount)                  AS AvgViewCount,
        AVG(p.Score)                      AS AvgScore,
        MAX(p.CreationDate) - MIN(p.CreationDate) AS TagLifetime
    FROM ParsedTags pt
    JOIN Posts p
      ON p.Id = pt.PostId
    GROUP BY pt.Tag
),
TopTags AS (
    SELECT
        Tag,
        QuestionCount,
        AvgViewCount,
        AvgScore,
        TagLifetime,
        ROW_NUMBER() OVER (ORDER BY QuestionCount DESC) AS TagRank
    FROM TagMetrics
),
UserActivity AS (
    SELECT
        u.Id                              AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COUNT(DISTINCT c.Id)              AS CommentCount,
        COUNT(DISTINCT b.Id)              AS BadgeCount,
        COALESCE(SUM(v.BountyAmount),0)    AS TotalBounty
    FROM Users u
    LEFT JOIN Posts p
      ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c
      ON c.UserId = u.Id
    LEFT JOIN Badges b
      ON b.UserId = u.Id
    LEFT JOIN Votes v
      ON v.UserId = u.Id
     AND v.VoteTypeId IN (8,9)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
EditedPosts AS (
    SELECT
        ph.PostId,
        COUNT(*)                         AS EditCount,
        MIN(ph.CreationDate)            AS FirstEdit,
        MAX(ph.CreationDate)            AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY ph.PostId
),
TopContributors AS (
    SELECT
        pt.Tag,
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount   AS UserQuestions,
        ua.AnswerCount,
        ua.CommentCount,
        ua.BadgeCount,
        ua.TotalBounty,
        ROW_NUMBER() OVER (PARTITION BY pt.Tag ORDER BY ua.Reputation DESC) AS RN
    FROM ParsedTags pt
    JOIN UserActivity ua
      ON ua.UserId = pt.OwnerId
),
Final AS (
    SELECT
        tt.Tag,
        tt.QuestionCount,
        tt.AvgScore,
        tt.AvgViewCount,
        tt.TagLifetime,
        tc.DisplayName     AS TopContributor,
        tc.Reputation,
        tc.UserQuestions,
        tc.AnswerCount,
        tc.CommentCount,
        tc.BadgeCount,
        tc.TotalBounty,
        ep.EditCount,
        ep.FirstEdit,
        ep.LastEdit
    FROM TopTags tt
    JOIN TopContributors tc
      ON tc.Tag = tt.Tag
     AND tc.RN = 1
    LEFT JOIN EditedPosts ep
      ON ep.PostId = (
             SELECT pt2.PostId
               FROM ParsedTags pt2
              WHERE pt2.Tag = tt.Tag
              ORDER BY pt2.CreationDate DESC
              LIMIT 1
         )
    WHERE tt.TagRank <= 10
)
SELECT *
FROM Final
ORDER BY QuestionCount DESC, AvgScore DESC, Reputation DESC;
