-- {"query": "186.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1602} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(vb.VoteScore),0) as VoteScoreSum
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join (
        select
            v.UserId,
            case
                when vt.Name = 'UpMod' then 1
                when vt.Name = 'DownMod' then -1
                else 0
            end as VoteScore
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        where v.UserId is not null
    ) vb on vb.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostWithLinkInfo as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        pl.RelatedPostId
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.LinkTypeId,
        p.LinkTypeName,
        p.RelatedPostId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserPostRank,
        rank() over (partition by p.PostTypeId order by p.Score desc) as PostTypeScoreRank
    from PostWithLinkInfo p
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.OwnerUserId as QuestionOwner,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViewCount,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        a.ViewCount as AnswerViewCount,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAcceptedAnswer,
        (select count(*) from Comments c where c.PostId = q.Id) as QuestionCommentCount,
        (select count(*) from Comments c where c.PostId = a.Id) as AnswerCommentCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
      and q.Score > 10
      and q.ViewCount > 1000
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadgeCount,
        count(b.Id) filter (where b.Class = 2) as SilverBadgeCount,
        count(b.Id) filter (where b.Class = 3) as BronzeBadgeCount,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
CloseReasonCounts as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, crt.Name
),
UserActivityWindow as (
    select
        ua.*,
        lag(ua.Reputation) over (order by ua.LastAccessDate) as PrevReputation,
        lead(ua.Reputation) over (order by ua.LastAccessDate) as NextReputation,
        row_number() over (order by ua.Reputation desc) as ReputationRank
    from RecursiveUserActivity ua
),
ComplexFilteredPosts as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.AcceptedAnswerId,
        array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1) as TagCount,
        case
            when p.ClosedDate is not null then 1
            else 0
        end as IsClosed,
        coalesce(crc.CloseCount, 0) as CloseVotesCount,
        crc.CloseReasonName
    from Posts p
    left join CloseReasonCounts crc on crc.PostId = p.Id
    where p.PostTypeId = 1
      and (p.Score > 5 or p.ViewCount > 500)
      and (p.ClosedDate is null or crc.CloseCount > 2)
)
select
    uaw.UserId,
    uaw.DisplayName,
    uaw.Reputation,
    uaw.QuestionCount,
    uaw.AnswerCount,
    uaw.CommentCount,
    uaw.GoldBadges,
    uaw.SilverBadges,
    uaw.BronzeBadges,
    uaw.VoteScoreSum,
    up.Title as TopQuestionTitle,
    up.Score as TopQuestionScore,
    up.ViewCount as TopQuestionViews,
    up.AcceptedAnswerId,
    up.IsClosed,
    up.CloseVotesCount,
    up.CloseReasonName,
    ub.GoldBadgeCount,
    ub.SilverBadgeCount,
    ub.BronzeBadgeCount,
    ub.LastBadgeDate,
    ua.PrevReputation,
    ua.NextReputation,
    ua.ReputationRank
from UserActivityWindow uaw
left join (
    select distinct on (OwnerUserId) Id, Title, Score, ViewCount, AcceptedAnswerId, ClosedDate is not null as IsClosed, 0 as CloseVotesCount, null::varchar as CloseReasonName, OwnerUserId
    from Posts
    where PostTypeId = 1
    order by OwnerUserId, Score desc, ViewCount desc
) up on up.OwnerUserId = uaw.UserId
left join UserBadgeSummary ub on ub.UserId = uaw.UserId
left join UserActivityWindow ua on ua.UserId = uaw.UserId
where uaw.Reputation > (
    select avg(Reputation) from Users
)
order by uaw.Reputation desc
limit 100;