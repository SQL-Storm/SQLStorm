-- {"query": "2323.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1252} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(vt2.VoteSum),0) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.CreationDate asc) as RankByReputation
    from 
        Users u
    left join (
        select 
            p.OwnerUserId,
            p.PostTypeId,
            p.Id
        from Posts p
        where p.OwnerUserId is not null
          and p.OwnerUserId > 0
    ) p on p.OwnerUserId = u.Id
    left join (
        select 
            v.PostId, 
            sum(case when vt.Id = 2 then 1 else 0 end) - sum(case when vt.Id = 3 then 1 else 0 end) as VoteSum
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by v.PostId
    ) vt2 on vt2.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.UpVotes, u.DownVotes
), UserBadges as (
    select 
        b.UserId,
        count(*) as BadgeCount,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        string_agg(distinct b.Name, ', ') as DistinctBadgeNames
    from Badges b
    group by b.UserId
), UserPostLatestComments as (
    select 
        c.PostId,
        c.UserId,
        c.UserDisplayName,
        c.CreationDate,
        c.Text,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as CommentRank
    from Comments c
    where c.UserId is not null
), QuestionsWithDuplicates as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.ViewCount,
        q.Score,
        q.OwnerUserId,
        dup.PostId as DuplicatePostId,
        dup.RelatedPostId as DuplicateOf,
        lt.Name as LinkTypeName
    from Posts q
    left join PostLinks dup on dup.PostId = q.Id and dup.LinkTypeId = 3 -- Duplicate links
    left join LinkTypes lt on lt.Id = dup.LinkTypeId
    where q.PostTypeId = 1
), QuestionCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as ClosedAt
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
), AnswerAcceptedStats as (
    select 
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        sum(case when p.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore
    from Posts p
    join Posts q on q.Id = p.ParentId and q.PostTypeId = 1
    where p.PostTypeId = 2
    group by p.ParentId
)
select 
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalVotesReceived,
    coalesce(ub.BadgeCount,0) as BadgeCount,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    substring(ub.DistinctBadgeNames from 1 for 100) as SampleBadges,
    qwd.QuestionId,
    qwd.Title,
    qwd.ViewCount,
    qwd.Score as QuestionScore,
    qwd.LinkTypeName as DuplicateLinkType,
    qcr.CloseReason,
    qcr.ClosedAt,
    aas.AnswerCount,
    aas.AcceptedAnswerCount,
    coalesce(aas.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(aas.MaxAnswerScore,0) as MaxAnswerScore,
    latest_comment.Text as LatestCommentText,
    latest_comment.CreationDate as LatestCommentDate
from RecursiveUserActivity ua
left join UserBadges ub on ub.UserId = ua.UserId
left join QuestionsWithDuplicates qwd on qwd.OwnerUserId = ua.UserId
left join QuestionCloseReasons qcr on qcr.PostId = qwd.QuestionId
left join AnswerAcceptedStats aas on aas.QuestionId = qwd.QuestionId
left join lateral (
    select uc.Text, uc.CreationDate
    from UserPostLatestComments uc
    where uc.PostId = qwd.QuestionId
    order by uc.CreationDate desc
    limit 1
) latest_comment on true
where ua.RankByReputation <= 50
and (qwd.QuestionId is not null or ua.QuestionCount > 10)
and (qcr.CloseReason is null or qcr.ClosedAt > ua.CreationDate)
order by ua.Reputation desc, qwd.ViewCount desc nulls last, qwd.Score desc nulls last
limit 100;