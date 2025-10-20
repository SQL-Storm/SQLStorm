with recursive RecursivePostReplies as (
    select p.Id, p.ParentId, 0 as Level, p.CreationDate
    from Posts p
    where p.PostTypeId = 1

    union all

    select child.Id, child.ParentId, r.Level + 1, child.CreationDate
    from Posts child
    join RecursivePostReplies r on child.ParentId = r.Id
    where child.PostTypeId = 2
),
RankedAcceptedAnswers as (
    select
        q.Id as QuestionId,
        a.Id as AcceptedAnswerId,
        rank() over (partition by q.Id order by coalesce(a.Score,0) desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    where q.PostTypeId = 1
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Name as BadgeName,
        dense_rank() over (partition by b.UserId order by b.Class) as BadgeClassRank,
        sum(case when b.TagBased then 1 else 0 end) over (partition by b.UserId) as TagBasedBadgeCount
    from Badges b
),
TopUserTags as (
    select
        u.Id as UserId,
        tag_json.TagName,
        row_number() over (partition by u.Id order by tag_json.TagCount desc) as TagRank
    from Users u
    cross join lateral (
        select t.TagName, count(*) as TagCount
        from Posts pq
        join unnest(string_to_array(substring(coalesce(pq.Tags,'<>'), 2, length(coalesce(pq.Tags,'') )-2), '><')) as t(TagName)
            on true
        where pq.PostTypeId = 1
          and pq.OwnerUserId = u.Id
        group by t.TagName
    ) tag_json
    where tag_json.TagCount > 5
),
PopularTags as (
    select t.Id, t.TagName, t.Count from Tags t
    where t.Count >=
      (select percentile_cont(0.75) within group (order by Count) from Tags)
),
QuestionCommentsCTE as (
    select
        c.Id, c.PostId, c.UserId, c.Score, c.Text,
        row_number() over (partition by c.PostId order by c.Score desc nulls last, c.CreationDate desc) as Ranking
    from Comments c
    join Posts p on c.PostId = p.Id
    where p.PostTypeId = 1
),
QuestionsWithPopularTags as (
    select p.*
    from Posts p
    where p.PostTypeId = 1
      and exists (
          select 1
          from unnest(string_to_array(substring(coalesce(p.Tags,'<>'), 2, length(coalesce(p.Tags,'') )-2), '><')) as tag(TagName)
          join PopularTags pt on pt.TagName = tag.TagName
      )
      and coalesce(p.ViewCount,0) > 5000
      and coalesce(p.Score,0) > 5
)
select distinct
       q.Id as QuestionId,
       q.Title,
       q.Score as QuestionScore,
       coalesce(qa.AcceptedAnswerId, -1) as AcceptedAnswerId,
       a.Score as AcceptedAnswerScore,
       u.DisplayName as QuestionOwner,
       u.Reputation as QuestionOwnerRepu,
       case when u.WebsiteUrl is null or length(u.WebsiteUrl) = 0 then 'NoUrl' else 'HasUrl' end as OwnerUrlFlag,
       usd.BadgeClassRank,
       usd.BadgeName,
       usd.TagBasedBadgeCount,
       commentsTop.Id as CommentId,
       commentsTop.Text as CommentText,
       commentsTop.Score as CommentScore,
       tagsTagTop.TagName as MostUsedTagByOwner,
       recursiveReplies.MaxReplyDepth,
       exists(select 1 from PostLinks pl where pl.PostId = q.Id and pl.LinkTypeId = 3) as HasDuplicateLink,
       (select count(1)
        from Votes v
        where v.PostId = q.Id and v.VoteTypeId = 2) as QuestionUpVotes,
       (select count(1)
        from Votes v
        where v.PostId in (select Id from Posts where ParentId = q.Id) and v.VoteTypeId = 2) as TotalAnswersUpVotes,
       case when q.ClosedDate is null then 'Open' else 'Closed' end as QuestionStatus,
       coalesce(crt.Name, 'Unknown') as CloseReasonName
from QuestionsWithPopularTags q
left join Posts a on a.Id = q.AcceptedAnswerId
left join RankedAcceptedAnswers qa on qa.QuestionId = q.Id and qa.AnswerRank = 1
left join Users u on u.Id = q.OwnerUserId
left join UserBadgeRanks usd on usd.UserId = u.Id and usd.BadgeClassRank = 1
left join QuestionCommentsCTE commentsTop on commentsTop.PostId = q.Id and commentsTop.Ranking = 1
left join LATERAL (
    select TagName
    from TopUserTags tut
    where tut.UserId = u.Id and tut.TagRank = 1
) tagsTagTop on true
left join (
    select r.ParentId as PostId, max(r.Level) as MaxReplyDepth
    from RecursivePostReplies r
    group by r.ParentId
) recursiveReplies on recursiveReplies.PostId = q.Id
left join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId = 10 and ph.CreationDate = (
    select max(PhInner.CreationDate)
    from PostHistory PhInner
    where PhInner.PostId = q.Id and PhInner.PostHistoryTypeId = 10
)
left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
where exists (
    select 1 from Users uinner where uinner.Id = q.OwnerUserId and uinner.Reputation > 1000
)
and (
     (coalesce(q.Score,0) * 2 + coalesce(a.Score,0)) > 20
     or coalesce((select sum(vc.BountyAmount) from Votes vc where vc.PostId = q.Id and vc.BountyAmount is not null), 0) > 50
)
order by q.Score desc, a.Score desc, recursiveReplies.MaxReplyDepth desc;