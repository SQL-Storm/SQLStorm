with RecursiveRecentEdits as (
  select ph.Id, ph.PostId, ph.CreationDate, ph.UserId, ph.PostHistoryTypeId
  from PostHistory ph
  where ph.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - interval '30 days')
), PerUserActivity as (
  select u.Id as UserId, u.DisplayName,
         coalesce(ed.DistinctPostsEdited, 0) as DistinctPostsEdited,
         coalesce(ed.TotalEdits, 0) as TotalEdits,
         coalesce(ed.filtered_posts, 0) as filtered_posts
  from Users u
  left join (
    select r.UserId,
           count(distinct r.PostId) as DistinctPostsEdited,
           count(*) filter (where pht.Name LIKE '%Edit%')  as TotalEdits,
           count(distinct p.PostTypeId) as filtered_posts
    from RecursiveRecentEdits r
    left join PostHistoryTypes pht on r.PostHistoryTypeId = pht.Id
    left join Posts p on p.Id = r.PostId
    group by r.UserId
  ) ed on ed.UserId = u.Id
), UserScoreAgg as (
  select u.Id as UserId,
    coalesce(sum(case when p.PostTypeId = 1 then p.Score else 0 end), 0) as QuestionScore,
    coalesce(sum(case when p.PostTypeId = 2 then p.Score else 0 end), 0) as AnswerScore,
    coalesce(sum(p.ViewCount),0) as ViewCounts
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id
), PostEnriched as (
  select p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate,
    p.Score, p.ViewCount,
    string_agg(distinct tag, ',' order by tag) as NormalizedTags,
    row_number() over(partition by p.OwnerUserId order by p.CreationDate desc) as RNLatestPerUser,
    min(p.CreationDate) over(partition by p.OwnerUserId) as FirstPostDate
  from Posts p
  left join lateral (
    select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as tag
    where p.Tags is not null
  ) tags on true
  group by p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount
), LinksFiltered as (
  select pl.PostId, pl.RelatedPostId, lt.Name as LinkName, pl.CreationDate
  from PostLinks pl join LinkTypes lt on lt.Id = pl.LinkTypeId
  where lt.Name in ('Linked','Duplicate')
), RecentBadges as (
  select b.UserId, b.Name, b.Class, b.Date,
         row_number() over (partition by b.UserId order by b.Date desc) as RN
  from Badges b
  where b.Date > (cast('2024-10-01 12:34:56' as timestamp) - interval '1 year')
), UserBadgeStrings as (
  select r.UserId,
         string_agg(r.Name || '(' ||
          case r.Class when 1 then 'G' when 2 then 'S' when 3 then 'B' else 'U' end || ')', ', ') as BadgeSummary
  from RecentBadges r
  where r.RN <= 5
  group by r.UserId
), QuestionScoresAndDuplicates as (
  select pq.Id, pq.OwnerUserId, pq.Score,
         count(distinct pd.Id) as DuplicateCount,
         max(case when lt.Name = 'Duplicate' then 'Yes' else 'No' end) as IsDuplicatedQuestion
  from Posts pq 
  left join PostLinks pd on pd.RelatedPostId = pq.Id
    and pd.LinkTypeId = (select Id from LinkTypes where Name = 'Duplicate' limit 1)
  left join LinkTypes lt on lt.Id = pd.LinkTypeId
  where pq.PostTypeId = 1
  group by pq.Id, pq.OwnerUserId, pq.Score
), UserQuestionRankings as (
  /* Rewritten to avoid ordered-set aggregate OVER() usage.
     Compute median per OwnerUserId using percentiles per OwnerUserId, then aggregate for overall median separately if needed.
     Here we compute per-user question count, total score, and rank users by total question score.
  */
  select q.OwnerUserId,
         rank() over(order by q.TotalQuestionScore desc nulls last) as UserQuestionScoreRank,
         q.QuestionCount,
         q.TotalQuestionScore
  from (
    select OwnerUserId,
           count(*) as QuestionCount,
           sum(Score) as TotalQuestionScore
    from Posts
    where PostTypeId = 1
    group by OwnerUserId
  ) q
), CombinedMetrics as (
  select u.Id as UserId, u.DisplayName,
         ua.DistinctPostsEdited, ua.TotalEdits,
         us.QuestionScore, us.AnswerScore, us.ViewCounts,
         utd.DuplicateCount, utd.IsDuplicatedQuestion,
         ub.BadgeSummary,
         uq.UserQuestionScoreRank, uq.QuestionCount, uq.TotalQuestionScore,
         (select count(*) 
          from Comments c 
          where c.UserId = u.Id
            and c.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - interval '180 days')
         ) as RecentCommentsCount       
  from Users u
  left join PerUserActivity ua            on ua.UserId = u.Id
  left join UserScoreAgg us              on us.UserId = u.Id
  left join QuestionScoresAndDuplicates utd  on utd.OwnerUserId = u.Id
  left join UserBadgeStrings ub          on ub.UserId = u.Id
  left join UserQuestionRankings uq      on uq.OwnerUserId = u.Id
)
select 
  cm.UserId, cm.DisplayName,
  coalesce(cm.DistinctPostsEdited,0)          AS EditedPostsLastM,
  coalesce(cm.TotalEdits,0)                    AS TotalEditsLastM,
  coalesce(cm.QuestionScore,0)                 AS SumQuestionScore,
  coalesce(cm.AnswerScore,0)                   AS SumAnswerScore,
  coalesce(cm.ViewCounts,0)                    AS TotalViewCountForPosts,
  coalesce(cm.DuplicateCount,0)                 AS UserDuplicatePostsLinked,
  coalesce(cm.IsDuplicatedQuestion, 'No')      as HasAllowedDups,
  coalesce(cm.BadgeSummary,'None')             AS RecentSomeBadges,
  coalesce(cm.UserQuestionScoreRank,null)      AS RankByQuestScores,
  NULL                                        AS Focus_UserMedianQCount,
  cm.QuestionCount                             AS QuestionCount,
  cm.TotalQuestionScore                        AS TotalQuestionScore,
  cm.RecentCommentsCount                       AS RecentCommentsCount
from CombinedMetrics cm
where cm.TotalQuestionScore > 3
order by cm.TotalQuestionScore desc
limit 100;