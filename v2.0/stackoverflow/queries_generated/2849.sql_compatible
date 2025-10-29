with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Class asc, b.Name) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation >= 1000
),
TopBadges as (
    select
        UserId,
        DisplayName,
        concat_ws(' | ',
            string_agg(
                distinct BadgeName || ' (' ||
                case Class
                    when 1 then 'Gold'
                    when 2 then 'Silver'
                    when 3 then 'Bronze'
                    else 'Unknown'
                end || ')', ', '
            )
        ) as BadgesList
    from RecursiveUserBadges
    where rn <= 10
    group by UserId, DisplayName
),
PopularQuestions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        p.Tags,
        u.Reputation as OwnerReputation,
        u.DisplayName as OwnerName,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
      and p.CreationDate between cast('2024-10-01 12:34:56' as timestamp) - interval '2 years' and cast('2024-10-01 12:34:56' as timestamp)
      and p.ViewCount > 1000
),
AnswersWithVotes as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
        count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
        sum(v.BountyAmount) as TotalBounty,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join Votes v on v.PostId = a.Id
    where a.PostTypeId = 2
    group by a.Id, a.ParentId, a.OwnerUserId, a.CreationDate, a.Score
),
AnswerOwnerReputation as (
    select
        a.AnswerId,
        u.Reputation,
        u.DisplayName
    from AnswersWithVotes a
    left join Users u on u.Id = a.OwnerUserId
),
QuestionCloseReasons as (
    select
        ph.PostId as QuestionId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
),
TopQuestionComments as (
    select distinct on (c.PostId)
        c.PostId,
        c.Text as TopCommentText,
        c.Score as TopCommentScore,
        c.CreationDate as CommentDate,
        coalesce(u.DisplayName, c.UserDisplayName) as CommentAuthor
    from Comments c
    left join Users u on u.Id = c.UserId
    order by c.PostId, c.Score desc nulls last, c.CreationDate asc
)
select
    pq.QuestionId,
    pq.Title,
    pq.OwnerUserId,
    pq.OwnerName,
    pq.OwnerReputation,
    tb.BadgesList,
    pq.ViewCount,
    pq.Score as QuestionScore,
    pq.AnswerCount,
    array_to_string(string_to_array(trim(both '<>' from pq.Tags), '><'), ', ') as TagList,
    case when pq.IsClosed = 1 then 'Closed' else 'Open' end as QuestionStatus,
    coalesce(qcr.CloseReasonName, 'N/A') as CloseReason,
    qcr.CloseDate,
    a.AnswerId,
    a.Score as AnswerScore,
    a.UpVotes,
    a.DownVotes,
    coalesce(a.TotalBounty, 0) as TotalBounty,
    a.AnswerRank,
    ao.DisplayName as AnswerOwner,
    ao.Reputation as AnswerOwnerReputation,
    tqc.TopCommentText,
    tqc.TopCommentScore,
    tqc.CommentDate,
    tqc.CommentAuthor,
    avg(a.Score) over (partition by pq.QuestionId) as AvgAnswerScore,
    (
        select count(*)
        from Comments c2
        where c2.PostId = pq.QuestionId
          and c2.UserId is not null
    ) as QuestionCommentCount,
    substring(pq.Title from 1 for 20) || ' - Answered by ' || coalesce(ao.DisplayName, 'Unknown') as TitleAnswerSnippet
from PopularQuestions pq
left join TopBadges tb on tb.UserId = pq.OwnerUserId
left join AnswersWithVotes a on a.QuestionId = pq.QuestionId and a.AnswerRank <= 3
left join AnswerOwnerReputation ao on ao.AnswerId = a.AnswerId
left join QuestionCloseReasons qcr on qcr.QuestionId = pq.QuestionId
left join TopQuestionComments tqc on tqc.PostId = pq.QuestionId
where pq.Tags is not null

union

select
    pq.QuestionId,
    pq.Title,
    pq.OwnerUserId,
    pq.OwnerName,
    pq.OwnerReputation,
    tb.BadgesList,
    pq.ViewCount,
    pq.Score as QuestionScore,
    pq.AnswerCount,
    array_to_string(string_to_array(trim(both '<>' from pq.Tags), '><'), ', ') as TagList,
    case when pq.IsClosed = 1 then 'Closed' else 'Open' end as QuestionStatus,
    coalesce(qcr.CloseReasonName, 'N/A') as CloseReason,
    qcr.CloseDate,
    null as AnswerId,
    null as AnswerScore,
    null as UpVotes,
    null as DownVotes,
    null as TotalBounty,
    null as AnswerRank,
    null as AnswerOwner,
    null as AnswerOwnerReputation,
    tqc.TopCommentText,
    tqc.TopCommentScore,
    tqc.CommentDate,
    tqc.CommentAuthor,
    null as AvgAnswerScore,
    (
        select count(*)
        from Comments c2
        where c2.PostId = pq.QuestionId
          and c2.UserId is not null
    ) as QuestionCommentCount,
    substring(pq.Title from 1 for 20) || ' - Answered by ' || 'N/A' as TitleAnswerSnippet
from PopularQuestions pq
left join TopBadges tb on tb.UserId = pq.OwnerUserId
left join QuestionCloseReasons qcr on qcr.QuestionId = pq.QuestionId
left join TopQuestionComments tqc on tqc.PostId = pq.QuestionId
where pq.Tags is not null
  and not exists (
      select 1 from AnswersWithVotes a where a.QuestionId = pq.QuestionId and a.AnswerRank <= 3
  )
order by ViewCount desc nulls last, QuestionScore desc nulls last, AnswerScore desc nulls last
limit 100;