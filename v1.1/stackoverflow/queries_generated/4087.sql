-- {"query": "4087.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1671} 
with RankedPosts as (
  select 
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    u.DisplayName as OwnerDisplayName,
    row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn,
    count(*) over (partition by p.PostTypeId) as total_posts
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId in (1,2)
),
UserBadgeStats as (
  select 
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    count(*) as TotalBadges
  from Badges b
  group by b.UserId
),
PostLinksSummary as (
  select 
    pl.PostId,
    count(case when pl.LinkTypeId = 1 then 1 end) as LinkedCount,
    count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateCount
  from PostLinks pl
  group by pl.PostId
),
VotesSummary as (
  select 
    v.PostId,
    count(case when vt.Name = 'UpMod' then 1 end) as UpVotes,
    count(case when vt.Name = 'DownMod' then 1 end) as DownVotes,
    sum(coalesce(v.BountyAmount,0)) as TotalBounty
  from Votes v
  join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
),
LatestPostHistory as (
  select distinct on (ph.PostId)
    ph.PostId,
    ph.PostHistoryTypeId,
    pht.Name as PostHistoryTypeName,
    ph.CreationDate,
    ph.UserId,
    ph.UserDisplayName,
    ph.Comment
  from PostHistory ph
  join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
  order by ph.PostId, ph.CreationDate desc
),
TagPopularity as (
  select 
    t.TagName,
    t.Count,
    coalesce(t.IsModeratorOnly,0) as IsModeratorOnly,
    coalesce(t.IsRequired,0) as IsRequired,
    row_number() over (order by t.Count desc) as PopularRank
  from Tags t
),
QuestionsWithPopularTags as (
  select
    p.Id as QuestionId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.Tags,
    array_agg(distinct tp.TagName order by tp.Count desc) filter (where tp.TagName is not null) as PopularTags,
    array_length(array_agg(distinct tp.TagName),1) as PopularTagCount
  from Posts p
  left join lateral (
    select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName
  ) tags on true
  left join TagPopularity tp on tp.TagName = tags.TagName and tp.PopularRank <= 5
  where p.PostTypeId = 1
  group by p.Id, p.Title, p.Score, p.ViewCount, p.Tags
),
AnswersWithAcceptedFlag as (
  select 
    a.Id,
    a.ParentId,
    case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted,
    a.Score,
    a.CreationDate,
    u.DisplayName as AnswerOwner,
    coalesce(vs.UpVotes,0) as UpVotes,
    coalesce(vs.DownVotes,0) as DownVotes
  from Posts a
  join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  left join Users u on u.Id = a.OwnerUserId
  left join VotesSummary vs on vs.PostId = a.Id
  where a.PostTypeId = 2
),
UserAccessWindow as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    lag(u.LastAccessDate) over (partition by u.Id order by u.LastAccessDate) as PrevAccess,
    lead(u.LastAccessDate) over (partition by u.Id order by u.LastAccessDate) as NextAccess,
    row_number() over (order by u.Reputation desc) as UserRank
  from Users u
  where u.Reputation > 1000
)
select
  rp.Id as PostId,
  rp.PostTypeId,
  rp.OwnerUserId,
  rp.OwnerDisplayName,
  rp.CreationDate,
  rp.Score,
  rp.ViewCount,
  rp.Tags,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  ubs.GoldBadges,
  ubs.SilverBadges,
  ubs.BronzeBadges,
  ubs.TotalBadges,
  pls.LinkedCount,
  pls.DuplicateCount,
  vs.UpVotes,
  vs.DownVotes,
  vs.TotalBounty,
  lph.PostHistoryTypeName as LastPostHistoryType,
  lph.UserDisplayName as LastPostEditor,
  qa.PopularTags,
  qa.PopularTagCount,
  aw.IsAccepted,
  aw.Score as AnswerScore,
  aw.AnswerOwner,
  ua.PrevAccess,
  ua.NextAccess,
  ua.UserRank,
  case 
    when rp.ClosedDate is not null then 'Closed' 
    when rp.FavoriteCount > 10 then 'Popular'
    else 'Normal'
  end as PostStatus,
  case 
    when rp.Tags like '%<sql>%'
      or rp.Title ilike '%sql%'
      then 1
    else 0 
  end as HasSQLTagOrTitle,
  -- complicated expression: normalized score with view count and age in days
  (rp.Score::float / nullif(greatest(rp.ViewCount,1),0)) * 
  (1 + least(30, extract(epoch from now() - rp.CreationDate)/86400)/30) as NormalizedScore
from RankedPosts rp
left join UserBadgeStats ubs on ubs.UserId = rp.OwnerUserId
left join PostLinksSummary pls on pls.PostId = rp.Id
left join VotesSummary vs on vs.PostId = rp.Id
left join LatestPostHistory lph on lph.PostId = rp.Id
left join QuestionsWithPopularTags qa on qa.QuestionId = rp.Id and rp.PostTypeId = 1
left join AnswersWithAcceptedFlag aw on aw.Id = rp.Id and rp.PostTypeId = 2
left join UserAccessWindow ua on ua.Id = rp.OwnerUserId
where rp.rn <= 100
union all
select
  rpr.Id as PostId,
  rpr.PostTypeId,
  rpr.OwnerUserId,
  rpr.OwnerDisplayName,
  rpr.CreationDate,
  rpr.Score,
  rpr.ViewCount,
  rpr.Tags,
  rpr.AnswerCount,
  rpr.CommentCount,
  rpr.FavoriteCount,
  null, null, null, null, null, null, null, null, null, null, null, null,
  'Summary' as PostStatus,
  null as HasSQLTagOrTitle,
  null as NormalizedScore
from RankedPosts rpr
where rpr.rn = 1 and rpr.total_posts > 1000
order by PostStatus desc, Score desc, ViewCount desc, PostId
limit 200;