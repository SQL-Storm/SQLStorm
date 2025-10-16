-- {"query": "1422.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1374} 
with recursive
UserBadgeRank as (
  select
    b.UserId,
    b.Name,
    b.Date,
    Dense_Rank() over (partition by b.UserId order by b.Date) as BadgeRankForUser
  from Badges b
  where b.Class = 1 -- gold badges only
),
UserFirstAndLastPost as (
  select
    p.OwnerUserId,
    min(p.CreationDate) as FirstPostDate,
    max(p.CreationDate) as LastPostDate
  from Posts p
  where p.OwnerUserId is not null
  group by p.OwnerUserId
),
QuestionAnswers enriched as (
  select
    q.Id as QuestionId,
    q.Title,
    q.OwnerUserId as QuestionOwner,
    q.CreationDate as QuestionCreation,
    q.Tags,
    a.Id as AnswerId,
    a.OwnerUserId as AnswerOwner,
    a.CreationDate as AnswerCreation,
    coalesce(a.Score,0) as AnswerScore,
    array_length(string_to_array(
          substring(coalesce(q.Tags, ''), 2, length(coalesce(q.Tags, ''))-2)
        ,'><'),1) as TagCount,
    (select avg(s.Score) from Posts s where s.ParentId = q.Id) as AvgAnswerScore,
    row_number() over (partition by q.Id order by coalesce(a.Score,0) desc, a.CreationDate asc) as AnswerRankByScore
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1
),
ActiveCloseReasons as (
   select ph.Comment as CloseReasonId, crt.Name as CloseReasonDetailedName
   from PostHistory ph
   join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
   where ph.PostHistoryTypeId = 10 -- Post Closed
   group by ph.Comment, crt.Name
   having count(*) > 10
),
PostsWithCloseInfo as (
  select
    p.Id,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    case when phc.Id is not null then 'Closed' else 'Open' end as PostStatus,
    phc.Comment as CloseReasonId,
    acr.CloseReasonDetailedName
  from Posts p
  left join PostHistory phc
    on phc.PostId = p.Id and phc.PostHistoryTypeId = 10
    and phc.CreationDate = (
        select max(phc2.CreationDate)
        from PostHistory phc2
        where phc2.PostId = p.Id and phc2.PostHistoryTypeId = 10
    )
  left join ActiveCloseReasons acr on acr.CloseReasonId = phc.Comment
)
select
  usr.Id as UserID,
  usr.DisplayName,
  usr.Reputation,
  min(p.IsQuestionSimulated) as HasAskedQuestion, -- 0 or 1
  count(distinct pclosed.Id) filter (where pclosed.PostStatus = 'Closed') as ClosedPosts,
  count(distinct pclosed.Id) filter (where pclosed.PostStatus = 'Open' and coalesce(pclosed.CloseReasonId, '') <> '') as PostWithCloseReasonButOpen,
  count(distinct ba.BadgeCountPerUser) as DifferentBadgesPossessed,
  avg(en.AnswerScore) filter (where en.AnswerRankByScore = 1) as AvgTopAnswerScore,
  max(en.TagCount) as MaxTagCountForUserQuestion,
  max(upari.BadgeRankForUser) as MaxGoldBadgeRankConsideringDates,
  oc.MaxCommentsOnAnswersPerQuestion,
  pCollCounts.InvolvedPostCount,
  case -- big switch for string phrase comb
    when max(pclosed.CloseReasonId) in ('101','1') then 'Most Duplicates'
    when max(pclosed.CloseReasonId) in ('102','2','3') then 'Off-topic possibly'
    else 'Miscellaneous Closing Reasons'
  end as TopClosingIssueCategory,
  substring(substr(coalesce(usr.AboutMe,''), 1, 300) || ..., 1, 300) as UserShortAboutSummary
from Users usr
left join UserBadgeRank upari on upari.UserId = usr.Id
left join (
  select distinct QuestionOwner, 1 as IsQuestionSimulated from QuestionAnswers enriched
) p on p.QuestionOwner = usr.Id
left join PostsWithCloseInfo pclosed on pclosed.OwnerUserId = usr.Id
left join (
  select
    qb.QuestionId,
    max(qb.CommentCount) over () as MaxCommentsOnAnswersPerQuestion
  from (
    select a.ParentId as QuestionId, count(c.Id) as CommentCount from Posts a
      left join Comments c on c.PostId = a.Id
    where a.PostTypeId = 2
    group by a.ParentId
    ) qb
) oc on oc.QuestionId = p.QuestionOwner
left join (
  select
    ube.UserId,
    count(distinct ube.Name) as BadgeCountPerUser
  from Badges ube
  group by ube.UserId
) ba on ba.UserId = usr.Id
left join QuestionAnswers enriched en on en.QuestionOwner = usr.Id and en.AnswerRankByScore = 1
left join (
  select pa.OwnerUserId, count(*) as InvolvedPostCount
  from Posts pa
  group by pa.OwnerUserId
) pCollCounts on pCollCounts.OwnerUserId = usr.Id
where usr.Reputation > 200
group by
  usr.Id,
  usr.DisplayName,
  usr.Reputation,
  oc.MaxCommentsOnAnswersPerQuestion,
  pCollCounts.InvolvedPostCount,
  TopClosingIssueCategory,
  substring(substr(coalesce(usr.AboutMe,''), 1, 300) || ..., 1, 300)
order by AvgTopAnswerScore desc nulls last, ClosedPosts desc, usr.Reputation desc
limit 100

union

select
  u1.Id,
  u1.DisplayName,
  u1.Reputation,
  0,
  0,
  0,
  null,
  null,
  null,
  null,
  0,
  'No Posts User',
  ''
from Users u1
left join Posts p1 on p1.OwnerUserId = u1.Id
where p1.Id is null
order by u1.Reputation desc
limit 50;