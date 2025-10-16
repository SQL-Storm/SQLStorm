-- {"query": "1589.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1294} 
with RecursivePostCounts as (
  select
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    count(a.Id) as DirectAnswerCount,
    coalesce(p.FavoriteCount,0) as FavoriteCount,
    -- Recursive CTE to walk comments about posts along post to post links for hierarchical tags effect
    1 as Depth
  from Posts p
  left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2 -- Answers only
  where p.PostTypeId = 1 -- questions only
  group by p.Id, p.Title, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.FavoriteCount

  union all

  select
    rl.RelatedPostId as Id,
    null,
    null,
    null,
    null,
    0,
    0,
    rpc.Depth + 1
  from PostLinks pl
  join RecursivePostCounts rpc on pl.PostId = rpc.Id
  join PostLinks rl on pl.RelatedPostId = rl.PostId
  where pl.LinkTypeId = 3 -- Duplicate links (chains of)
    and rpc.Depth < 5
),
BadgesRanks as (
  select
    UserId,
    Name,
    max(Class) as MaxClass,
    count(*) as BadgeCount,
    max(Date) filter (where Class = 1) as LastGoldBadgeDate,
    dense_rank() over (partition by UserId order by max(Class) desc) as RankByClass
  from Badges b
  group by UserId, Name
),
UserAggregates as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
    count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
    sum(aux.DirectAnswerCount) as TotalDirectAnswers,
    coalesce(sum(voteup.UpVotes),0) as TotalUpvotes,
    coalesce(sum(votedown.DownVotes),0) as TotalDownvotes,
    count(b.Id) as UserBadgeCount,
    max(b.Date) as LatestBadgeDate,
    /* Calculate % of Posts without closure in last year */
    avg(case when ph14.PostHistoryTypeId = 10 then 0.0 else 1.0 end) filter (where p.CreationDate > NOW() - interval '1 year') as PercentWithoutClose
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join RecursivePostCounts aux on aux.Id = p.Id
  left join Badges b on b.UserId = u.Id
  left join Votes voteup on voteup.UserId = u.Id and voteup.VoteTypeId = 2
  left join Votes votedown on votedown.UserId = u.Id and votedown.VoteTypeId = 3
  left join LATERAL (
    select ph.PostHistoryTypeId
    from PostHistory ph
    where ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    order by ph.CreationDate desc limit 1
  ) as ph14 on true
  group by u.Id, u.DisplayName, u.Reputation
),
LatestComments on Posts as (
  select
    c.PostId,
    row_number() over (partition by c.PostId order by c.CreationDate desc) as RowNum,
    trimmedText,
    length(c.Text) as TextLength,
    coalesce(c.UserDisplayName, 'Guest') as Presenter
  from (
     select
       c.PostId, 
       trim(left(replace(replace(regexp_replace(c.Text, '<[^>]*>', '', 'g'), Chr(10), ' '), Chr(13), ' '), 80)) as trimmedText,
       c.Text,
       c.UserDisplayName
     from Comments c
  ) c
)
select 
  u.Id,
  u.DisplayName,
  u.Reputation,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.TotalDirectAnswers,
  ua.TotalUpvotes,
  ua.TotalDownvotes,
  ua.UserBadgeCount,
  ua.LatestBadgeDate,
  ua.PercentWithoutClose,
  bc.Name as TopBadgeName,
  bc.MaxClass as TopBadgeClass,
  tagSubjects.TagList,
  perctest.PercentileScoredPosts,
  laps.Last10CommentDetail
from 
  Users u
  join UserAggregates ua on ua.Id = u.Id
  left join (
    select br.UserId, string_agg(Name, ', ') TagList
    from BadgesRanks br
    where br.MaxClass = (select max(Class) from Badges where User = br.UserId)
    group by br.UserId
  ) as tagSubjects on tagSubjects.UserId = u.Id
  left join (
    select
      ub.UserId,
      percentile_cont(0.95) within group (order by p.Score) as PercentileScoredPosts
    from UserAggregates ua
    join Posts p on p.OwnerUserId = ua.Id and p.CreationDate > NOW() - interval '2 year'
    group by ub.UserId
  ) as perctest on perctest.UserId = u.Id
  left join (
    select
      c.PostId,
      ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) ranking,
      '[' || safe_json_array_agg(json_build_object('text', c.trimmedText, 'author', c.Presenter, 'length', c.TextLength ORDER BY c.CreationDate DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW )) || ']' as Last10CommentDetail
    from LatestComments c
    where c.RowNum between 1 and 10
    group by c.PostId
  ) as laps on laps.PostId = u.Id
order by ua.TotalUpvotes desc
limit 100;