with
AuthorActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    count(distinct case when p.PostTypeId = 1 then p.Id end) as Questions,
    count(distinct case when p.PostTypeId = 2 then p.Id end) as Answers,
    coalesce(c.CommentCount,0) as Comments,
    coalesce(sum(case when ph.PostHistoryTypeId in (12,13) then 1 else 0 end),0) as DeletionEvents,
    (
      cast(count(distinct case when p.PostTypeId = 1 then p.Id end) as numeric) * 1.0
      + cast(count(distinct case when p.PostTypeId = 2 then p.Id end) as numeric) * 0.6
      + cast(coalesce(c.CommentCount,0) as numeric) * 0.2
      - coalesce(sum(case when ph.PostHistoryTypeId in (12) then 0.5 when ph.PostHistoryTypeId in (13) then 0.2 else 0 end),0)
    ) as WeightedActivity
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join PostHistory ph on ph.UserId = u.Id
  left join (
    select UserId, count(*) as CommentCount from Comments where UserId is not null group by UserId
  ) c on c.UserId = u.Id
  group by u.Id, u.DisplayName, c.CommentCount
),
QuestionTags as (
  select
    q.Id as QuestionId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    lower(trim(tag)) as Tag
  from Posts q
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(q.Tags,''),2, greatest(length(coalesce(q.Tags,''))-2,0)),'><')) as tag
  ) t
  where q.PostTypeId = 1
    and q.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
TagMetrics as (
  select
    t.Tag,
    count(distinct t.QuestionId) as QuestionCount,
    avg(t.Score) as AvgScore,
    sum(t.ViewCount) as TotalViews,
    sum(case when t.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days' then 1 else 0 end) as Last30,
    count(*) as Last365,
    case when count(*) = 0 then 0 else (cast(sum(case when t.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days' then 1 else 0 end) as numeric) / cast(count(*) as numeric)) end as TrendingRatio
  from QuestionTags t
  group by t.Tag
),
RelatedPostsAgg as (
  select
    pl.PostId,
    pl.RelatedPostId,
    string_agg(distinct lt.Name, ',' order by lt.Name) as LinkTypeNames,
    max(pl.CreationDate) as LatestLinkDate
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  group by pl.PostId, pl.RelatedPostId
),
QuestionScores as (
  select
    q.Id,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    (select count(*) from (
       select unnest(string_to_array(substring(coalesce(q.Tags,''),2,greatest(length(coalesce(q.Tags,''))-2,0)),'><')) as t
    ) s) as TagCount,
    (select count(*) from Badges b where b.UserId = q.OwnerUserId and b.Class = 1 and b.Date <= q.CreationDate) as GoldBefore,
    (select count(distinct coalesce(c.UserId,-1)) from Comments c where c.PostId = q.Id) as UniqueCommenters,
    (select count(*) from PostLinks pl where pl.PostId = q.Id) as RelatedLinkCount,
    (select string_agg(distinct lt.Name,',') from PostLinks pl join LinkTypes lt on lt.Id = pl.LinkTypeId where pl.PostId = q.Id) as RelatedLinkTypes,
    cast(greatest(extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - q.CreationDate))/86400.0, 0) as numeric(10,2)) as DaysSinceCreation,
    (
      (q.Score * 3.0)
      + ln(greatest(q.ViewCount,1)) * 2.2
      + sqrt(greatest(q.AnswerCount,0)+1) * 5
      + q.FavoriteCount * 4
      + coalesce((select Reputation from Users u2 where u2.Id = q.OwnerUserId),0) * 0.01
      - least(greatest(extract(epoch from (cast('2024-10-01 12:34:56' as timestamp)-q.LastActivityDate))/86400.0,0)/365.0,2.0) * 10
    ) as RenaissanceScore
  from Posts q
  where q.PostTypeId = 1
    and q.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
TopAuthors as (
  select *
  from (
    select
      aa.*,
      row_number() over (order by aa.WeightedActivity desc NULLS LAST, aa.Questions desc) as rn
    from AuthorActivity aa
  ) x
  where rn <= 50
),
TopAuthorTopQuestions as (
  select
    ta.UserId,
    ta.DisplayName,
    qs.Id as QuestionId,
    qs.Title,
    qs.RenaissanceScore,
    qs.TagCount,
    qs.DaysSinceCreation,
    qs.GoldBefore,
    qs.UniqueCommenters,
    qs.RelatedLinkCount,
    qs.RelatedLinkTypes,
    row_number() over (partition by ta.UserId order by qs.RenaissanceScore desc) as RankWithinAuthor
  from TopAuthors ta
  join Posts p on p.OwnerUserId = ta.UserId and p.PostTypeId = 1
  join QuestionScores qs on qs.Id = p.Id
),
AnswerAggregates as (
  select
    a.ParentId as QuestionId,
    count(*) as AnswerCountAll,
    sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswers,
    sum(case when a.Score < 0 then 1 else 0 end) as NegativeAnswers,
    avg(a.Score) as AvgAnswerScore,
    max(a.Score) as MaxAnswerScore,
    min(a.Score) as MinAnswerScore,
    bool_or(a.Id = p.AcceptedAnswerId) as HasAcceptedInSet
  from Posts a
  left join Posts p on p.Id = a.ParentId
  where a.PostTypeId = 2
  group by a.ParentId
),
VoteAggregates as (
  select
    v.PostId,
    sum(case when vt.Name = 'UpMod' then 1 when vt.Name = 'DownMod' then -1 else 0 end) as VoteDelta,
    count(*) as VoteCount,
    sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteVotes
  from Votes v
  left join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.PostId
)
select
  taq.UserId,
  taq.DisplayName,
  taq.QuestionId,
  left(taq.Title,200) as ShortTitle,
  taq.RenaissanceScore,
  taq.TagCount,
  taq.DaysSinceCreation,
  taq.GoldBefore,
  taq.UniqueCommenters,
  taq.RelatedLinkCount,
  coalesce(taq.RelatedLinkTypes,'') as RelatedLinkTypes,
  aa.AnswerCountAll,
  aa.PositiveAnswers,
  aa.NegativeAnswers,
  aa.AvgAnswerScore,
  va.VoteDelta,
  va.VoteCount,
  va.FavoriteVotes,
  case
    when taq.DaysSinceCreation = 0 then taq.RenaissanceScore
    when va.VoteCount is null then taq.RenaissanceScore * 0.9
    else (taq.RenaissanceScore * (1 + cast(greatest(coalesce(va.VoteCount,0),1) as numeric) / 100.0))
  end as AdjustedScore,
  (
    'Tags:' || coalesce((select string_agg(distinct t.Tag,',') from QuestionTags t where t.QuestionId = taq.QuestionId), 'none')
    || '; Links:' || coalesce(taq.RelatedLinkTypes,'none')
    || '; Comments:' || coalesce(cast(taq.UniqueCommenters as text),'0')
    || '; Fav:' || coalesce(cast(va.FavoriteVotes as text),'0')
  ) as CompactSummary,
  case
    when coalesce(qs.ViewCount,0) > 10000 and coalesce(aa.AnswerCountAll,0) = 0 then 'HighViewNoAnswers'
    when coalesce(va.VoteDelta,0) < -5 then 'Downvoted'
    when taq.GoldBefore >= 1 and taq.RenaissanceScore > 100 then 'ExpertHot'
    else NULL
  end as Flags,
  taq.RankWithinAuthor
from TopAuthorTopQuestions taq
left join QuestionScores qs on qs.Id = taq.QuestionId
left join AnswerAggregates aa on aa.QuestionId = taq.QuestionId
left join VoteAggregates va on va.PostId = taq.QuestionId
group by
  taq.UserId,
  taq.DisplayName,
  taq.QuestionId,
  left(taq.Title,200),
  taq.RenaissanceScore,
  taq.TagCount,
  taq.DaysSinceCreation,
  taq.GoldBefore,
  taq.UniqueCommenters,
  taq.RelatedLinkCount,
  taq.RelatedLinkTypes,
  aa.AnswerCountAll,
  aa.PositiveAnswers,
  aa.NegativeAnswers,
  aa.AvgAnswerScore,
  va.VoteDelta,
  va.VoteCount,
  va.FavoriteVotes,
  qs.ViewCount,
  taq.RankWithinAuthor
order by taq.UserId, taq.RankWithinAuthor, AdjustedScore desc;