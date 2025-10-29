-- {"query": "2336.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1194} 
with RECURSIVE TagHierarchy(tagId, ParentTagId, Depth) as (
  select t.Id, null::int, 0
  from Tags t
  where t.IsRequired=1
  union all
  select c.Id, p.Id, h.Depth + 1
  from Tags c
  join TagHierarchy h on h.tagId = c.Id - 1  -- hypothetical parent id as Id-1 to create recursion
  join Tags p on p.Id = h.tagId
  where c.IsModeratorOnly = 0
),
UserBadgeRank as (
  select 
    u.Id as UserId,
    u.DisplayName,
    count(b.Id) filter (where b.Class = 1) as GoldBadges,
    count(b.Id) filter (where b.Class = 2) as SilverBadges,
    count(b.Id) filter (where b.Class = 3) as BronzeBadges,
    row_number() over (order by count(b.Id) desc, u.Reputation desc) as Rank
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName
),
PostStats as (
  select 
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AcceptedAnswerId,
    coalesce(a.Score, 0) as AcceptedAnswerScore,
    coalesce(cmt.CommentCount, 0) as CommentCount,
    dense_rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank
  from Posts p
  left join Posts a on a.Id = p.AcceptedAnswerId
  left join (
    select PostId, count(*) as CommentCount
    from Comments
    group by PostId
  ) cmt on cmt.PostId = p.Id
  where p.PostTypeId in (1,2)
),
PostHistoryAnalysis as (
  select
    ph.PostId,
    ph.PostHistoryTypeId,
    pht.Name as HistoryTypeName,
    count(*) as ChangesCount,
    max(ph.CreationDate) as LastChangeDate,
    bool_or(ph.UserId is null) as HasAnonymousEdit,
    count(distinct ph.UserId) as DistinctEditors
  from PostHistory ph
  join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
  where ph.PostId in (select Id from Posts where PostTypeId = 1)
  group by ph.PostId, ph.PostHistoryTypeId, pht.Name
),
LatestUserActivity as (
  select
    u.Id,
    u.DisplayName,
    max(coalesce(p.LastActivityDate, u.LastAccessDate)) as LatestActivityDate,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes,
    coalesce(string_agg(distinct coalesce(t.TagName, 'None'), ', '), 'No Tags') as TagsInvolved,
    sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
    sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Votes v on v.UserId = u.Id
  left join lateral (
    select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName
  ) t on true
  group by u.Id, u.DisplayName
),
DuplicatesAndLinks as (
  select
    pl.PostId,
    pl.RelatedPostId,
    lt.Name as LinkTypeName,
    p1.Title as PostTitle,
    p2.Title as RelatedPostTitle
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  join Posts p1 on p1.Id = pl.PostId
  join Posts p2 on p2.Id = pl.RelatedPostId
  where pl.LinkTypeId in (1,3)
)
select 
  u.DisplayName as User,
  u.Reputation,
  ub.GoldBadges,
  ub.SilverBadges,
  ub.BronzeBadges,
  psa.Id as PostId,
  psa.PostTypeId,
  psa.Score,
  psa.ViewCount,
  psa.Title,
  psa.CommentCount,
  psa.AcceptedAnswerScore,
  pha.ChangesCount,
  pha.DistinctEditors,
  la.LatestActivityDate,
  la.TotalUpVotes,
  la.TotalDownVotes,
  la.TagsInvolved,
  dup.LinkTypeName,
  dup.PostTitle,
  dup.RelatedPostTitle,
  case 
    when psa.CommentCount > 10 and psa.Score < 0 then 'Controversial'
    when psa.Score > 50 then 'Popular'
    else 'Normal'
  end as PostPopularityCategory
from Users u
join UserBadgeRank ub on ub.UserId = u.Id
left join PostStats psa on psa.OwnerUserId = u.Id
left join PostHistoryAnalysis pha on pha.PostId = psa.Id
left join LatestUserActivity la on la.Id = u.Id
left join DuplicatesAndLinks dup on dup.PostId = psa.Id
where psa.ScoreRank <= 100 or psa.ScoreRank is null
order by ub.Rank, psa.Score desc nulls last
limit 100;