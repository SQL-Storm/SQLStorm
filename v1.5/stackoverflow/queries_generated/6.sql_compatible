WITH RECURSIVE RecursiveCTE AS (
    SELECT P1.Id AS OriginalPostId,
           P2.Id AS RelatedPostId,
           0 AS Level
    FROM Posts P1
    JOIN PostLinks PL ON P1.Id = PL.PostId
    JOIN Posts P2 ON PL.RelatedPostId = P2.Id
    WHERE PL.LinkTypeId = 1

    UNION ALL

    SELECT RC.OriginalPostId,
           P.Id,
           RC.Level + 1
    FROM RecursiveCTE RC
    JOIN PostLinks PL ON RC.RelatedPostId = PL.PostId
    JOIN Posts P ON PL.RelatedPostId = P.Id
    WHERE RC.Level < 3
)
SELECT *
FROM RecursiveCTE;