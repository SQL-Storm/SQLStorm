WITH RecursiveTagCounts AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        COUNT(p.Id) AS QuestionPostCount,
        COUNT(DISTINCT p.OwnerUserId) FILTER (WHERE p.OwnerUserId IS NOT NULL) AS ContributedUsers
    FROM Tags t
    LEFT JOIN Posts p
        ON CAST(t.Id AS TEXT) = CAST(p.tags AS TEXT)
    GROUP BY t.Id, t.TagName
)
SELECT
    rtc.TagId,
    rtc.TagName,
    rtc.QuestionPostCount,
    rtc.ContributedUsers
FROM RecursiveTagCounts rtc;