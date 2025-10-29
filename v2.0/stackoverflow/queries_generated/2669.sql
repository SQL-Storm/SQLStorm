-- {"query": "2669.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1291} 
with
UserActivity as (
  select 
    u.Id as UserId,
    u.DisplayName,
    count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
    count(distinct a.Id) as AnswerCount,
    coalesce(sum(vtUp.VotesCount),0) as TotalUpVotesReceived,
    coalesce(sum(vtDown.VotesCount),0) as TotalDownVotesReceived,
    max(p.CreationDate) as LastPostDate,
    row_number() over(partition by u.Id order by p.CreationDate desc nulls last) as rn_posts
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2 -- answers to user's questions
  left join (
    select PostId, count(*) as VotesCount from Votes where VoteTypeId = 2 group by PostId
  ) vtUp on vtUp.PostId = p.Id
  left join (
    select PostId, count(*) as VotesCount from Votes where VoteTypeId = 3 group by PostId
  ) vtDown on vtDown.PostId = p.Id
  group by u.Id, u.DisplayName
),
TopTags as (
  select 
    t.TagName,
    t.Count,
    p.OwnerUserId,
    row_number() over (partition by p.OwnerUserId order by t.Count desc, t.TagName) as rn_tag
  from Posts p
  join LATERAL (
    select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName
  ) tagsUnnested on true
  join Tags t on t.TagName = tagsUnnested.TagName
  where p.PostTypeId = 1 and p.OwnerUserId is not null
),
UserTopTags as (
  select
    OwnerUserId as UserId,
    string_agg(TagName, ', ' order by rn_tag) as TopTags
  from TopTags
  where rn_tag <= 3
  group by OwnerUserId
),
PostCloseReasons as (
  select ph.PostId, crt.Name as CloseReasonName, max(ph.CreationDate) as CloseDate
  from PostHistory ph
  join CloseReasonTypes crt on crt.Id = ph.Comment::int
  where ph.PostHistoryTypeId = 10 and ph.Comment ~ '^\d+$' -- ensure Comment is an integer matching CloseReasonTypes.Id
  group by ph.PostId, crt.Name
),
UserBadgesRanked as (
  select 
    b.UserId, b.Name, b.Class, b.Date,
    row_number() over(partition by b.UserId order by b.Class, b.Date desc) as rn_badge
  from Badges b
),
UserTopBadges as (
  select 
    UserId,
    string_agg(Name || ' (' || 
      case Class when 1 then 'Gold' when 2 then 'Silver' when 3 then 'Bronze' else 'Unknown' end
    || ')', ', ' order by rn_badge) as TopBadges
  from UserBadgesRanked
  where rn_badge <= 5
  group by UserId
)
select 
  ua.UserId,
  ua.DisplayName,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.TotalUpVotesReceived,
  ua.TotalDownVotesReceived,
  ua.LastPostDate,
  ut.TopTags,
  ub.TopBadges,
  ph.PostId,
  p.Title,
  p.Score,
  p.ViewCount,
  coalesce(p.FavoriteCount,0) as FavoriteCount,
  case when p.ClosedDate is not null then 'Closed' else 'Open' end as PostStatus,
  p.Tags,
  p.CreationDate,
  cr.CloseReasonName,
  dense_rank() over (partition by ua.UserId order by p.Score desc nulls last) as PostScoreRank,
  lag(p.Score) over (partition by ua.UserId order by p.CreationDate) as PrevPostScore,
  lead(p.Score) over (partition by ua.UserId order by p.CreationDate) as NextPostScore,
  coalesce(
    (select count(*) from Comments c where c.PostId = p.Id and c.UserId = ua.UserId),
    0) as UserCommentsOnPost,
  length(p.Body) - length(replace(p.Body, '<code>', '')) as CodeSnippetCount,
  substring(p.Body from 'href="([^"]+)"') as FirstHref,
  case when position('<javascript>' in lower(p.Body)) > 0 then 1 else 0 end as HasJavaScriptTag
from UserActivity ua
left join Posts p on p.OwnerUserId = ua.UserId
left join PostCloseReasons cr on cr.PostId = p.Id
left join UserTopTags ut on ut.UserId = ua.UserId
left join UserTopBadges ub on ub.UserId = ua.UserId
where ua.QuestionCount > 10
union
select 
  u.Id as UserId,
  u.DisplayName,
  0 as QuestionCount,
  0 as AnswerCount,
  0 as TotalUpVotesReceived,
  0 as TotalDownVotesReceived,
  null as LastPostDate,
  null as TopTags,
  null as TopBadges,
  null as PostId,
  null as Title,
  null as Score,
  null as ViewCount,
  null as FavoriteCount,
  'Open' as PostStatus,
  null as Tags,
  null as CreationDate,
  null as CloseReasonName,
  null as PostScoreRank,
  null as PrevPostScore,
  null as NextPostScore,
  0 as UserCommentsOnPost,
  0 as CodeSnippetCount,
  null as FirstHref,
  0 as HasJavaScriptTag
from Users u
where u.Id not in (select UserId from UserActivity)
order by DisplayName nulls last, PostScoreRank nulls last, p.CreationDate desc nulls last;