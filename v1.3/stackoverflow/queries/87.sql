with
QuestionBase as (
  select p.Id as QuestionId,
         p.Title,
         coalesce(p.OwnerUserId, -1) as OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.Tags,
         case when p.Tags is null then cast(array[] as text[]) else regexp_split_to_array(trim(both '<>' from p.Tags), '><') end as TagArray,
         p.AnswerCount,
         p.AcceptedAnswerId
  from Posts p
  where p.PostTypeId = 1
),
AnswerStats as (
  select a.ParentId as QuestionId,
         count(case when a.Score > 0 then 1 end) as PositiveAnswers,
         count(case when a.Score <= 0 then 1 end) as NonPositiveAnswers,
         avg(a.Score) as AvgAnswerScore,
         max(a.Score) as MaxAnswerScore,
         min(a.Score) as MinAnswerScore,
         sum(case when a.OwnerUserId is null then 0 else 1 end) as AnsweredByRegistered,
         (select a2.Id
          from Posts a2
          where a2.ParentId = a.ParentId and a2.PostTypeId = 2
          order by a2.Score desc nulls last, a2.CreationDate asc
          limit 1) as TopAnswerId,
         percentile_disc(0.5) within group (order by a.Score) as MedianAnswerScore
  from Posts a
  where a.PostTypeId = 2
  group by a.ParentId
),
UserEngagement as (
  select u.Id as UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate as UserSince,
         u.LastAccessDate,
         (select count(*) from Posts p where p.OwnerUserId = u.Id) as OwnedPosts,
         (select count(*) from Comments c where c.UserId = u.Id) as CommentsCount,
         (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 2) as UpvotesCast,
         (select count(*) from Badges b where b.UserId = u.Id) as BadgesEarned,
         case when u.Reputation > 0 then (select count(*) from Posts p where p.OwnerUserId = u.Id) / nullif(cast(u.Reputation as numeric),0) else null end as PostsPerReputation
  from Users u
  where u.Reputation >= 50
),
TagScoring as (
  select t.Id as TagId,
         t.TagName,
         t.Count as DeclaredCount,
         coalesce(tp.RealCount,0) as RealCount,
         coalesce(tp.RealCount,0) - t.Count as CountDelta,
         (ln(coalesce(tp.RealCount,0) + 1) * 0.6 + sqrt(coalesce(tp.RealCount,0) + 1) * 0.4) *
           (case when t.IsModeratorOnly = true then 0.5 when t.IsRequired = true then 1.2 else 1 end) as PopularityScore
  from Tags t
  left join (
    select unnest_tag as TagName, count(*) as RealCount
    from (
      select distinct q.Id,
             unnest(q_tag) as unnest_tag
      from (
        select Id, case when Tags is null then cast(array[] as text[]) else regexp_split_to_array(trim(both '<>' from Tags), '><') end as q_tag
        from Posts
        where PostTypeId = 1
      ) q
    ) s
    group by unnest_tag
  ) tp on lower(tp.TagName) = lower(t.TagName)
),
LinkGraph as (
  select pl.PostId,
         pl.RelatedPostId,
         pl.LinkTypeId,
         pl.CreationDate,
         lt.Name as LinkTypeName,
         p1.PostTypeId as PostType_Left,
         p2.PostTypeId as PostType_Right,
         coalesce(p1.Score,0) as LeftScore,
         coalesce(p2.Score,0) as RightScore
  from PostLinks pl
  left join LinkTypes lt on lt.Id = pl.LinkTypeId
  left join Posts p1 on p1.Id = pl.PostId
  left join Posts p2 on p2.Id = pl.RelatedPostId
  where pl.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
CombinedMetrics as (
  select q.QuestionId,
         q.Title,
         q.OwnerUserId,
         q.CreationDate,
         q.Score as QuestionScore,
         q.ViewCount,
         q.Tags,
         qs.PopularityScore,
         coalesce(a.PositiveAnswers,0) as PositiveAnswers,
         coalesce(a.NonPositiveAnswers,0) as NonPositiveAnswers,
         coalesce(a.AvgAnswerScore,0) as AvgAnswerScore,
         coalesce(a.MaxAnswerScore,0) as MaxAnswerScore,
         coalesce(a.MedianAnswerScore,0) as MedianAnswerScore,
         ue.DisplayName as OwnerName,
         ue.Reputation as OwnerReputation,
         (coalesce(q.Score,0) * 0.7 + coalesce(a.AvgAnswerScore,0) * 0.2 + coalesce(q.ViewCount,0)/nullif(greatest(date_part('day', cast('2024-10-01 12:34:56' as timestamp) - q.CreationDate),1),0) * 0.1) as AgeWeightedScore,
         0.5 * (coalesce(q.Score,0) / nullif(max(coalesce(q.Score,0)) over (),1)) +
         0.3 * (coalesce(q.ViewCount,0) / nullif(max(coalesce(q.ViewCount,0)) over (),1)) +
         0.2 * (coalesce(a.PositiveAnswers,0) / nullif(max(coalesce(a.PositiveAnswers,0)) over (),1)) as CompositeHotness,
         case when array_length(q.TagArray,1) >= 1 then lower(q.TagArray[1]) else null end as PrimaryTag
  from QuestionBase q
  left join AnswerStats a on a.QuestionId = q.QuestionId
  left join UserEngagement ue on ue.UserId = q.OwnerUserId
  left join TagScoring qs on lower(q.TagArray[1]) = lower(qs.TagName)
),
Ranked as (
  select cm.PrimaryTag,
         cm.QuestionId,
         cm.Title,
         cm.OwnerUserId,
         cm.OwnerName,
         cm.OwnerReputation,
         cm.CompositeHotness,
         cm.AgeWeightedScore,
         cm.PositiveAnswers,
         cm.NonPositiveAnswers,
         cm.AvgAnswerScore,
         cm.MedianAnswerScore,
         cm.PopularityScore,
         row_number() over (partition by cm.PrimaryTag order by cm.CompositeHotness desc nulls last, cm.AgeWeightedScore desc nulls last) as TagRank,
         dense_rank() over (order by cm.CompositeHotness desc nulls last) as GlobalDenseRank,
         ntile(10) over (order by cm.CompositeHotness desc nulls last) as HotnessDecile
  from CombinedMetrics cm
  where cm.CompositeHotness is not null
    and cm.CompositeHotness > 0
)
select r.PrimaryTag,
       r.TagRank,
       r.GlobalDenseRank,
       r.HotnessDecile,
       r.QuestionId,
       left(r.Title, 200) as TitleSnippet,
       r.OwnerUserId,
       r.OwnerName,
       r.OwnerReputation,
       round(cast(r.CompositeHotness as numeric),6) as CompositeHotness,
       round(cast(r.AgeWeightedScore as numeric),6) as AgeWeightedScore,
       r.PositiveAnswers,
       r.NonPositiveAnswers,
       r.AvgAnswerScore,
       r.MedianAnswerScore,
       r.PopularityScore,
       (select string_agg(coalesce(c.UserDisplayName,'[anon]') || ':' || left(coalesce(c.Text,''),140), ' ||| ' order by c.CreationDate desc)
        from Comments c
        where c.PostId = r.QuestionId
          and c.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
        limit 3
       ) as RecentCommentsSnippet,
       exists (select 1 from PostLinks pl where pl.PostId = r.QuestionId and pl.LinkTypeId = 3) as HasDuplicates,
       exists (select 1 from PostLinks pl where pl.RelatedPostId = r.QuestionId and pl.LinkTypeId = 1) as IsLinkedFromOthers
from Ranked r
where (r.OwnerReputation > 500 or r.PopularityScore > 10 or r.PositiveAnswers >= 3)
  and not (r.PrimaryTag is null and r.PopularityScore < 1)
order by r.GlobalDenseRank
limit 250;