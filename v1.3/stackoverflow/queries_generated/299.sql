-- {"query": "299.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4375} 
with
recent_posts as (
  select
    p.*,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerReputation,
    (select count(*) from Comments c where c.PostId = p.Id) as CommentsComputed,
    (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotesComputed,
    (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotesComputed,
    (select min(a.CreationDate) from Posts a where a.ParentId = p.Id and a.PostTypeId = 2) as FirstAnswerDate
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.CreationDate >= current_date - interval '365 days' OR p.Score is not null
),
tag_exploded as (
  select
    rp.Id as PostId,
    trim(t.tag) as TagName,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Title
  from recent_posts rp
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(rp.Tags,''), 2, greatest(length(coalesce(rp.Tags,'')) - 2,0)), '><')) as tag
  ) t
  where coalesce(rp.Tags,'') <> ''
),
per_tag_stats as (
  select
    te.TagName,
    count(distinct te.PostId) as PostsInYear,
    avg(case when te.PostTypeId = 1 then te.Score::numeric end) as AvgQScore,
    sum(case when te.PostTypeId = 1 then te.ViewCount else 0 end) as TotalQViews,
    sum(case when te.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
    max(te.Score) as MaxScore,
    substring(string_agg(distinct coalesce(te.Title,'') , ' || ' order by te.CreationDate desc), 1, 1000) as RecentTitlesSample
  from tag_exploded te
  group by te.TagName
  having count(distinct te.PostId) > 5
),
tag_ranked as (
  select
    *,
    row_number() over (order by PostsInYear desc nulls last, AvgQScore desc nulls last, TotalQViews desc nulls last) as TagRank
  from per_tag_stats
),
user_stats as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    (select count(*) from Posts q where q.OwnerUserId = u.Id and q.PostTypeId = 1) as Questions,
    (select count(*) from Posts a where a.OwnerUserId = u.Id and a.PostTypeId = 2) as Answers,
    coalesce((
      select sum(case when v2.VoteTypeId = 2 then 1 when v2.VoteTypeId = 3 then -1 else 0 end)
      from Votes v2
      join Posts p2 on p2.Id = v2.PostId
      where p2.OwnerUserId = u.Id
    ),0) as VoteScore,
    (select max(p3.Score) from Posts p3 where p3.OwnerUserId = u.Id) as BestPostScore,
    (select count(*) from Badges b where b.UserId = u.Id and b.Class = 1) as GoldBadges,
    (select count(*) from Badges b where b.UserId = u.Id and b.Class = 2) as SilverBadges,
    (select count(*) from Badges b where b.UserId = u.Id and b.Class = 3) as BronzeBadges,
    (
      select avg(extract(epoch from (fa.FirstAnswer - q.CreationDate))/3600.0) -- average hours to first answer
      from Posts q
      cross join lateral (
        select min(a.CreationDate) as FirstAnswer
        from Posts a
        where a.ParentId = q.Id and a.PostTypeId = 2
      ) fa
      where q.PostTypeId = 1 and q.OwnerUserId = u.Id and fa.FirstAnswer is not null
    ) as AvgFirstAnswerHours,
    (select max(uh.LastAccessDate) from Users uh where uh.Id = u.Id) as LastSeen
  from Users u
  where u.Reputation is not null
),
user_ranked as (
  select
    us.*,
    dense_rank() over (order by Reputation desc nulls last, Answers desc nulls last) as UserRank,
    row_number() over (order by Answers desc nulls last, Questions desc nulls last) as ActivityRank
  from user_stats us
),
user_top_tag as (
  select
    te.OwnerUserId as UserId,
    te.TagName,
    count(*) as PostsInTag,
    row_number() over (partition by te.OwnerUserId order by count(*) desc, max(te.CreationDate) desc) as rn
  from tag_exploded te
  group by te.OwnerUserId, te.TagName
),
user_preferred_tag as (
  select UserId, TagName, PostsInTag from user_top_tag where rn = 1
),
set_ops as (
  (
    select p.Id, p.Title, 'high_score' as reason from Posts p where p.Score >= 50
  )
  union
  (
    select p.Id, p.Title, 'high_view' as reason from Posts p where p.ViewCount >= 100000
  )
  except
  (
    select p.Id, p.Title, 'few_comments' as reason from Posts p where coalesce(p.CommentCount,0) < 3
  )
),
exemplary_posts_by_tag as (
  select distinct te.TagName, s.Id as PostId, s.Title, s.reason
  from set_ops s
  join Posts p on p.Id = s.Id
  join tag_exploded te on te.PostId = p.Id
  where te.TagName is not null
),
combined as (
  select
    coalesce(tr.TagName, upt.TagName) as TagName,
    tr.TagRank,
    tr.PostsInYear,
    tr.AvgQScore,
    tr.TotalQViews,
    ur.UserId,
    ur.DisplayName as UserName,
    ur.Reputation as UserReputation,
    ur.Questions,
    ur.Answers,
    ur.VoteScore,
    upt.PostsInTag as UserPostsInThisTag,
    ur.AvgFirstAnswerHours,
    ep.PostId as NotablePostId,
    ep.Title as NotablePostTitle,
    ep.reason as NotableReason,
    case
      when tr.TagName is null then 'tag_missing'
      when ur.UserId is null then 'user_missing'
      else 'matched'
    end as MatchStatus,
    now() as SnapshotTime
  from tag_ranked tr
  full outer join user_preferred_tag upt on upt.TagName = tr.TagName
  left join user_ranked ur on ur.UserId = upt.UserId
  left join exemplary_posts_by_tag ep on ep.TagName = coalesce(tr.TagName, upt.TagName)
)
select
  TagName,
  TagRank,
  PostsInYear,
  coalesce(round(AvgQScore::numeric,2),0) as AvgQuestionScore,
  TotalQViews,
  UserId,
  UserName,
  UserReputation,
  Questions,
  Answers,
  VoteScore,
  coalesce(UserPostsInThisTag,0) as UserPostsInThisTag,
  coalesce(round(AvgFirstAnswerHours::numeric,2), null) as AvgFirstAnswerHours,
  NotablePostId,
  substring(coalesce(NotablePostTitle,''),1,120) as NotablePostTitleSnippet,
  NotableReason,
  MatchStatus,
  SnapshotTime,
  -- percentile rank of this tag by PostsInYear among all tags (window)
  percent_rank() over (order by coalesce(PostsInYear,0) desc) as TagPostsPercentRank,
  -- small heuristic score combining multiple signals
  (coalesce(PostsInYear,0) * 0.4 + coalesce(TotalQViews,0) * 0.0001 + coalesce(AvgQuestionScore,0) * 2 + coalesce(UserReputation,0) * 0.0005 + coalesce(UserPostsInThisTag,0) * 1.5) as HeuristicScore
from combined
where (coalesce(PostsInYear,0) > 0 or coalesce(UserPostsInThisTag,0) > 0)
order by HeuristicScore desc nulls last
limit 250;