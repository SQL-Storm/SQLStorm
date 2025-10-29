with RankedAnswers as (
    select 
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(*) over (partition by a.ParentId) as TotalAnswers
    from Posts a
    inner join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
QuestionStats as (
    select
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        q.OwnerUserId,
        u.DisplayName as QuestionOwnerName,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as UpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as DownVotes,
        case when q.ClosedDate is null then 0 else 1 end as IsClosed,
        case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join Comments c on c.PostId = q.Id
    left join Votes v on v.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, q.OwnerUserId, u.DisplayName, q.ClosedDate, q.AcceptedAnswerId
),
TopAnswerWithComments as (
    select
        ra.Id as AnswerId,
        ra.ParentId,
        ra.Score as AnswerScore,
        ra.CreationDate as AnswerCreation,
        ra.UserId as AnswerUserId,
        ra.DisplayName as AnswerUserName,
        ra.Reputation as AnswerUserReputation,
        (select count(*) from Comments c where c.PostId = ra.Id) as AnswerCommentCount,
        ra.AnswerRank,
        ra.TotalAnswers
    from RankedAnswers ra
    where ra.AnswerRank = 1
)
select 
    qs.Id as QuestionId,
    qs.Title,
    qs.QuestionScore,
    qs.ViewCount,
    qs.CommentCount as QuestionCommentCount,
    qs.UpVotes,
    qs.DownVotes,
    qs.IsClosed,
    qs.HasAcceptedAnswer,
    qs.OwnerUserId,
    qs.QuestionOwnerName,
    tawc.AnswerId as TopAnswerId,
    tawc.AnswerScore,
    tawc.AnswerCreation,
    tawc.AnswerUserId,
    tawc.AnswerUserName,
    tawc.AnswerUserReputation,
    tawc.AnswerCommentCount,
    tawc.TotalAnswers,
    case 
        when qs.Tags IS NOT NULL then 
            -- aggregate tags truncated to 5 chars, ensure ORDER BY expression appears in arguments of DISTINCT aggregate
            (select string_agg(t.trunc_tag, ',' ORDER BY t.tag)
             from (
                 select distinct tag, left(tag,5) as trunc_tag
                 from (
                     select unnest(string_to_array(substr(qs.Tags,2,length(qs.Tags)-2), '><')) as tag
                 ) s
             ) t
            )
        else 'NoTags'
    end as ShortTagList,
    coalesce(badge_counts.BadgeCount,0) as OwnerBadgeCount,
    power(qs.QuestionScore, 1.5) + ln(1 + qs.ViewCount) - coalesce(tawc.AnswerUserReputation / 1000.0, 0) as WeightedPopularityScore
from QuestionStats qs
left join TopAnswerWithComments tawc on tawc.ParentId = qs.Id
left join lateral (
    select unnest(string_to_array(substr(qs.Tags,2,length(qs.Tags)-2), '><')) as tag
) tags on true
left join (
    select UserId, count(*) as BadgeCount
    from Badges
    group by UserId
) badge_counts on badge_counts.UserId = qs.OwnerUserId
where 
    (qs.ViewCount > 1000 or qs.QuestionScore > 10)
    and (tawc.AnswerScore is null or tawc.AnswerScore > 5)
group by
    qs.Id,
    qs.Title,
    qs.QuestionScore,
    qs.ViewCount,
    qs.CommentCount,
    qs.UpVotes,
    qs.DownVotes,
    qs.IsClosed,
    qs.HasAcceptedAnswer,
    qs.OwnerUserId,
    qs.QuestionOwnerName,
    tawc.AnswerId,
    tawc.AnswerScore,
    tawc.AnswerCreation,
    tawc.AnswerUserId,
    tawc.AnswerUserName,
    tawc.AnswerUserReputation,
    tawc.AnswerCommentCount,
    tawc.TotalAnswers,
    qs.Tags,
    badge_counts.BadgeCount
order by WeightedPopularityScore desc
limit 50;