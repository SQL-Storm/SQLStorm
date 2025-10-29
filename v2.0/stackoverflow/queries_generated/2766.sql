-- {"query": "2766.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1589} 
with RecursiveTagCounts as (
  select
    p.Id as PostId,
    unnest(string_to_array(substring(coalesce(p.Tags, ''), 2, length(coalesce(p.Tags, '')) - 2), '><')) as Tag,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId
  from Posts p
  where p.PostTypeId = 1

  union all

  select
    p.Id as PostId,
    unnest(string_to_array(substring(coalesce(p.Tags, ''), 2, length(coalesce(p.Tags, '')) - 2), '><')) as Tag,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId
  from Posts p
  where p.PostTypeId = 1
),
UserAggregates as (
  select
    u.Id as UserId,
    u.DisplayName,
    count(distinct b.Id) as BadgeCount,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    min(p.CreationDate) as FirstPostDate,
    max(p.LastActivityDate) as LastActiveDate,
    max(p.Score) as MaxPostScore,
    avg(p.Score) as AvgPostScore,
    count(p.Id) as TotalPosts
  from Users u
  left join Badges b on b.UserId = u.Id
  left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1, 2)
  group by u.Id, u.DisplayName
),
TopPostsByTags as (
  select 
    Tag,
    PostId,
    Score,
    row_number() over (partition by Tag order by Score desc, ViewCount desc) as TagRank
  from RecursiveTagCounts rtc
),
AcceptedAnswerStats as (
  select
    q.Id as QuestionId,
    q.Title as QuestionTitle,
    q.OwnerUserId,
    a.Id as AcceptedAnswerId,
    a.Score as AcceptedAnswerScore,
    a.CreationDate as AnswerCreationDate,
    u.DisplayName as AskedBy,
    u.Reputation as UserReputation,
    (select avg(v.Score) from Posts v where v.OwnerUserId = q.OwnerUserId and v.PostTypeId = 2) as AvgAnswerScoreByAsker,
    (select count(*) from Comments c where c.PostId = q.Id) as CommentCount,
    (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as UpVotes,
    (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 3) as DownVotes
  from Posts q
  left join Posts a on a.Id = q.AcceptedAnswerId
  left join Users u on u.Id = q.OwnerUserId
  where q.PostTypeId = 1
    and q.AcceptedAnswerId is not null
),
PostsWithCloseInfo as (
  select
    p.Id,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    cht.Name as LastCloseType,
    cht.Id as LastCloseTypeId,
    ph.CreationDate as CloseDate,
    prc.Name as CloseReason
  from Posts p
  left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
  left join CloseReasonTypes prc on cast(ph.Comment as int) = prc.Id
  left join PostHistoryTypes cht on ph.PostHistoryTypeId = cht.Id
  where p.PostTypeId = 1
),
WindowedUserPosts as (
  select
    p.Id,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserTopPostRank,
    lag(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as PrevScore,
    lead(p.Score) over (partition by p.OwnerUserId order by p.CreationDate) as NextScore
  from Posts p
  where p.OwnerUserId is not null
    and p.PostTypeId in (1, 2)
),
FinalReport as (
  select
    u.Id as UserId,
    u.DisplayName,
    ua.BadgeCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.FirstPostDate,
    ua.LastActiveDate,
    ua.MaxPostScore,
    ua.AvgPostScore,
    ua.TotalPosts,
    pwt.Title as TopPostTitle,
    pwt.Score as TopPostScore,
    pwt.ViewCount as TopPostViewCount,
    pwt.CreationDate as TopPostCreationDate,
    aps.QuestionTitle,
    aps.AcceptedAnswerId,
    aps.AcceptedAnswerScore,
    aps.AskedBy,
    aps.UserReputation,
    aps.AvgAnswerScoreByAsker,
    aps.CommentCount,
    aps.UpVotes,
    aps.DownVotes,
    pwi.LastCloseType,
    pwi.CloseReason,
    wup.UserTopPostRank,
    wup.PrevScore,
    wup.NextScore
  from Users u
  left join UserAggregates ua on ua.UserId = u.Id
  left join lateral (
    select p.Title, p.Score, p.ViewCount, p.CreationDate
    from Posts p
    where p.OwnerUserId = u.Id
      and p.PostTypeId in (1, 2)
    order by p.Score desc, p.ViewCount desc
    limit 1
  ) pwt on true
  left join LATERAL (
    select aps.*
    from AcceptedAnswerStats aps
    where aps.OwnerUserId = u.Id
    order by aps.AcceptedAnswerScore desc
    limit 1
  ) aps on true
  left join PostsWithCloseInfo pwi on pwi.Id = aps.QuestionId
  left join WindowedUserPosts wup on wup.OwnerUserId = u.Id and wup.UserTopPostRank = 1
  where u.Reputation > 1000
)
select 
  UserId,
  DisplayName,
  BadgeCount,
  GoldBadges,
  SilverBadges,
  BronzeBadges,
  FirstPostDate,
  LastActiveDate,
  MaxPostScore,
  round(AvgPostScore::numeric,2) AvgPostScore,
  TotalPosts,
  TopPostTitle,
  TopPostScore,
  TopPostViewCount,
  TopPostCreationDate,
  QuestionTitle as MostImpactfulQuestion,
  AcceptedAnswerId,
  AcceptedAnswerScore,
  AskedBy,
  UserReputation,
  round(coalesce(AvgAnswerScoreByAsker,0)::numeric,2) AvgAnswerScoreByAsker,
  CommentCount,
  UpVotes,
  DownVotes,
  LastCloseType,
  CloseReason,
  UserTopPostRank,
  PrevScore,
  NextScore
from FinalReport
where (GoldBadges + SilverBadges + BronzeBadges) > 0
order by BadgeCount desc nulls last, MaxPostScore desc, TotalPosts desc
limit 100;