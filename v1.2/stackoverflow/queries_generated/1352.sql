-- {"query": "1352.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1536} 
with recursive RecursivePostsCTE as (
  select
    p.Id,
    p.PostTypeId,
    p.ParentId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    0 as Depth,
    array[p.Id] as Path
  from Posts p
  where p.ParentId is null

  union all

  select
    child.Id,
    child.PostTypeId,
    child.ParentId,
    child.Score,
    child.ViewCount,
    child.CreationDate,
    child.OwnerUserId,
    parent.Depth + 1,
    parent.Path || child.Id
  from Posts child
  inner join RecursivePostsCTE parent on child.ParentId = parent.Id
  where child.Id not in (select unnest(parent.Path))
),
LatestPostVotes as (
  select
    p.Id as PostId,
    count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
    count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
    count(v.Id) filter (where v.VoteTypeId in (6,7)) as CloseReopenVotes,
    max(v.CreationDate) as LastVoteDate
  from Posts p
  left join Votes v on v.PostId = p.Id
  group by p.Id
),
PostCommentsSummary as (
  select
    c.PostId,
    count(*) as TotalComments,
    count(distinct c.UserId) as DistinctCommenters,
    max(c.CreationDate) as LastCommentDate,
    string_agg(coalesce nullif(c.UserDisplayName, ''), ' | ' order by c.CreationDate desc) as RecentCommenters
  from Comments c
  group by c.PostId
),
UserActivityStats as (
  select 
    u.Id as UserId,
    u.DisplayName,
    count(distinct case when p.PostTypeId = 1 then p.Id else null end) as QuestionCount,
    count(distinct case when p.PostTypeId = 2 then p.Id else null end) as AnswerCount,
    count(distinct b.Id) as BadgeCount,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    row_number() over (partition by 1 order by u.Reputation desc nulls last) as ReputationRank,
    dense_rank() over (order by u.CreationDate) as SignupOrder,
    bool_or(b.TagBased = 1) as HasTagBasedBadge
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostCloseReasonsCTE as (
  select
    ph.PostId,
    crt.Name as CloseReasonName,
    ph.CreationDate as CloseDate,
    ph.UserId as CloserUserId,
    u.DisplayName as CloserUserName
  from PostHistory ph
  join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
  left join Users u on u.Id = ph.UserId
  where ph.PostHistoryTypeId = 10 -- Post Closed event
),
UnansweredPopularQuestions as (
  select 
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    lpv.UpVotes,
    lpv.DownVotes,
    lpv.CloseReopenVotes,
    pcs.TotalComments,
    uas.DisplayName as OwnerDisplayName,
    uas.ReputationRank,
    dense_rank() over (order by p.Score desc) as ScoreRankDesc,
    rank() over (partition by p.OwnerUserId order by p.CreationDate) as UserPostSequence
  from Posts p
  left join LatestPostVotes lpv on lpv.PostId = p.Id
  left join PostCommentsSummary pcs on pcs.PostId = p.Id
  left join UserActivityStats uas on uas.UserId = p.OwnerUserId
  where p.PostTypeId = 1 and (p.AcceptedAnswerId is null or p.AcceptedAnswerId = 0)
    and p.Score > ( select avg(score) from posts where posttypeid = 1 ) -- Above avg score questions only
    and (lpv.UpVotes is null or lpv.UpVotes > 5) -- at least some upvotes (could be higher to focus)
    and p.ClosedDate is null
)
select 
  upq.Id as QuestionId,
  upq.Title,
  upq.Score,
  upq.ViewCount,
  upq.UpVotes,
  upq.DownVotes,
  upq.TotalComments,
  upq.OwnerDisplayName,
  upq.ReputationRank,
  upq.ScoreRankDesc,
  upq.UserPostSequence,
  pdefcount.ParentAnswerCount,
  prc.CloseReasonName,
  prc.CloserUserName,
  uact.HasTagBasedBadge,
  string_agg(distinct concat('PostID:', c.Id, ' Commenter:', coalesce(c.UserDisplayName,'[anon]')), '; ' order by c.CreationDate) as CommentDetails,
  max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 19) over (partition by upq.Id) as ProtectedDate,
  avg(rpst.Depth) over () as AvgReplyDepth
from UnansweredPopularQuestions upq
left join Posts pdefcount on pdefcount.ParentId = upq.Id and pdefcount.PostTypeId = 2
left join PostCloseReasonsCTE prc on prc.PostId = upq.Id
left join Comments c on c.PostId = upq.Id or c.PostId = pdefcount.Id
left join PostHistory ph on ph.PostId = upq.Id
left join UserActivityStats uact on uact.UserId = prc.CloserUserId
left join RecursivePostsCTE rpst on rpst.Id = pdefcount.Id
group by 
  upq.Id,
  upq.Title,
  upq.Score,
  upq.ViewCount,
  upq.UpVotes,
  upq.DownVotes,
  upq.TotalComments,
  upq.OwnerDisplayName,
  upq.ReputationRank,
  upq.ScoreRankDesc,
  upq.UserPostSequence,
  pdefcount.ParentAnswerCount,
  prc.CloseReasonName,
  prc.CloserUserName,
  uact.HasTagBasedBadge
union -- string concat test with set operator
select
  p.Id,
  null,
  count(v.Id),
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null
from Posts p
left join Votes v on v.PostId = p.Id and v.VoteTypeId = 14
group by p.Id
order by ReputationRank nulls last, ScoreRankDesc nulls last
limit 100;