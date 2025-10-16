-- {"query": "808.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1470} 
with RecursiveUserActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
    count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
    coalesce(sum(vtup.UpVotes), 0) as TotalUpVotes,
    coalesce(sum(vtdn.DownVotes), 0) as TotalDownVotes
  from
    Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
      select PostId, count(*) as UpVotes from Votes where VoteTypeId = 2 group by PostId
    ) vtup on vtup.PostId = p.Id
    left join (
      select PostId, count(*) as DownVotes from Votes where VoteTypeId = 3 group by PostId
    ) vtdn on vtdn.PostId = p.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
  union all
  select
    r.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.CreationDate,
    ru.LastAccessDate,
    r.QuestionCount,
    r.AnswerCount,
    r.TotalUpVotes,
    r.TotalDownVotes
  from RecursiveUserActivity r
  join Users ru on ru.Id = r.UserId
  where r.Reputation > 10000
  limit 100
),
PostAggregates as (
  select
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.Title,
    p.AcceptedAnswerId,
    p.ParentId,
    count(c.Id) as CommentCount,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as rn
  from
    Posts p
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
  group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.Title, p.AcceptedAnswerId, p.ParentId
),
TopPosts as (
  select * from PostAggregates where rn <= 5
),
QuestionsWithAcceptedAnswer as (
  select
    q.Id as QuestionId,
    q.Title as QuestionTitle,
    q.Score as QuestionScore,
    q.ViewCount as QuestionViews,
    q.Tags,
    a.Id as AnswerId,
    a.Score as AnswerScore,
    a.OwnerUserId as AnswerOwnerId,
    a.CreationDate as AnswerCreationDate,
    u.DisplayName as AnswerOwnerName,
    (select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2) as AnswerUpVotes,
    (select count(*) from Comments c where c.PostId = a.Id and c.CreationDate > q.CreationDate) as NewCommentsAfterQuestion
  from
    Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
  where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
LinkStats as (
  select
    pl.PostId,
    lt.Name as LinkTypeName,
    count(distinct pl.RelatedPostId) as LinkCount
  from
    PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
  group by pl.PostId, lt.Name
),
BadgeRanks as (
  select
    b.UserId,
    b.Name,
    b.Class,
    row_number() over (partition by b.UserId order by b.Date desc) as BadgeRank
  from Badges b
),
UserBadgeSummary as (
  select
    UserId,
    count(case when Class = 1 then 1 end) as GoldBadges,
    count(case when Class = 2 then 1 end) as SilverBadges,
    count(case when Class = 3 then 1 end) as BronzeBadges
  from Badges
  group by UserId
),
PostsWithCloseInfo as (
  select
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.ClosedDate,
    crt.Name as CloseReasonName,
    ph.Comment as CloseReasonCode,
    ph.CreationDate as CloseVoteDate
  from
    Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id::int = ph.Comment::int
  where p.PostTypeId = 1 and p.ClosedDate is not null
)
select
  ru.UserId,
  ru.DisplayName,
  ru.Reputation,
  ru.QuestionCount,
  ru.AnswerCount,
  ru.TotalUpVotes,
  ru.TotalDownVotes,
  coalesce(ubs.GoldBadges, 0) as GoldBadges,
  coalesce(ubs.SilverBadges, 0) as SilverBadges,
  coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
  tp.Id as TopPostId,
  tp.Title as TopPostTitle,
  tp.Score as TopPostScore,
  tp.ViewCount as TopPostViews,
  tp.Tags as TopPostTags,
  qwa.QuestionId,
  qwa.QuestionTitle,
  qwa.QuestionScore,
  qwa.QuestionViews,
  qwa.AnswerId,
  qwa.AnswerScore,
  qwa.AnswerOwnerId,
  qwa.AnswerOwnerName,
  qwa.AnswerUpVotes,
  qwa.NewCommentsAfterQuestion,
  ls.LinkTypeName,
  ls.LinkCount,
  pci.Title as ClosedQuestionTitle,
  pci.CloseReasonName,
  pci.CloseVoteDate
from
  RecursiveUserActivity ru
  left join UserBadgeSummary ubs on ubs.UserId = ru.UserId
  left join TopPosts tp on tp.OwnerUserId = ru.UserId and tp.rn = 1
  left join QuestionsWithAcceptedAnswer qwa on qwa.AnswerOwnerId = ru.UserId
  left join LinkStats ls on ls.PostId = tp.Id
  left join PostsWithCloseInfo pci on pci.Id = tp.Id
where
  ru.Reputation > 5000
order by
  ru.Reputation desc,
  tp.Score desc
limit 200;