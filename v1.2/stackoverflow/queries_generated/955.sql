-- {"query": "955.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1232} 
with RankedAnswers as (
    select
        a.Id,
        a.ParentId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        u.Reputation as OwnerReputation,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as rn
    from Posts a
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
), QuestionStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.CreationDate,
        q.AcceptedAnswerId,
        u.DisplayName as QuestionOwnerName,
        u.Reputation as QuestionOwnerReputation,
        count(distinct c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        max(ph.CreationDate) as LastEditDate,
        -- Extract first tag (if any)
        split_part(trim(both '<>' from q.Tags), '><', 1) as FirstTag
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    left join Comments c on q.Id = c.PostId
    left join Votes v on q.Id = v.PostId
    left join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId in (4,5,6)
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.OwnerUserId, q.Score, q.ViewCount, q.CreationDate, q.AcceptedAnswerId, u.DisplayName, u.Reputation
), TopAnswerDetails as (
    select
        ra.ParentId as QuestionId,
        ra.Id as AnswerId,
        ra.OwnerUserId,
        ra.CreationDate,
        ra.Score,
        ra.OwnerReputation,
        u.DisplayName as AnswerOwnerName
    from RankedAnswers ra
    left join Users u on ra.OwnerUserId = u.Id
    where ra.rn = 1
), CloseInfo as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
), UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
), UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        count(distinct p.Id) as PostCount,
        count(distinct c.Id) as CommentCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
)
select
    qs.QuestionId,
    qs.Title,
    coalesce(ci.CloseReason, 'Open') as CloseStatus,
    qs.QuestionOwnerName,
    qs.QuestionOwnerReputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    qs.QuestionScore,
    qs.ViewCount,
    qs.CommentCount,
    qs.UpVotes,
    qs.DownVotes,
    qs.FirstTag,
    coalesce(tad.AnswerId, -1) as TopAnswerId,
    tad.Score as TopAnswerScore,
    tad.AnswerOwnerName,
    tad.OwnerReputation as AnswerOwnerReputation,
    ua.PostCount as OwnerPostCount,
    ua.CommentCount as OwnerCommentCount,
    -- Complex calculated field: weighted score difference normalized by days since creation
    case
        when extract(epoch from (now() - qs.CreationDate)) / 86400 > 0 then
            round( (qs.QuestionScore - coalesce(tad.Score,0))::numeric / (extract(epoch from (now() - qs.CreationDate)) / 86400), 4)
        else null
    end as ScoreDiffPerDay,
    -- String expression with NULL logic
    concat('Q: ', qs.Title, ' [Tag: ', coalesce(qs.FirstTag, 'none'), ']', ' - Owner: ', coalesce(qs.QuestionOwnerName, 'Anonymous')) as QuestionSummary
from QuestionStats qs
left join CloseInfo ci on qs.QuestionId = ci.PostId
left join TopAnswerDetails tad on qs.QuestionId = tad.QuestionId
left join UserBadgeSummary ubs on qs.OwnerUserId = ubs.UserId
left join UserActivity ua on qs.OwnerUserId = ua.UserId
where qs.ViewCount > 1000
  and (qs.Tags is not null and qs.Tags like '%<sql>%')
  and exists (
      select 1 from Posts p2
      where p2.ParentId = qs.QuestionId and p2.Score > 10
  )
order by ScoreDiffPerDay desc nulls last, qs.ViewCount desc
limit 100;