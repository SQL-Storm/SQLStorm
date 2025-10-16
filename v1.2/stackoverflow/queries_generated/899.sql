-- {"query": "899.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1500} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        0 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        c.Id,
        c.TagName,
        c.Count,
        r.Level + 1,
        r.Path || c.Id
    from Tags c
    join RecursiveTagHierarchy r on c.Id != all(r.Path)
    where c.IsModeratorOnly = 0 and c.IsRequired = 0 and r.Level < 2
),
UserBadgesStats as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LatestBadgeDate
    from Badges b
    group by b.UserId
),
TopAnswerers as (
    select
        p.OwnerUserId,
        count(p.Id) as AnswerCount,
        avg(p.Score) as AvgScore,
        sum(p.Score) as TotalScore,
        max(p.CreationDate) as LastAnswerDate,
        row_number() over (partition by p.OwnerUserId order by max(p.CreationDate) desc) as rn
    from Posts p
    where p.PostTypeId = 2 and p.OwnerUserId is not null
    group by p.OwnerUserId
    having count(p.Id) > 10
),
QuestionDetails as (
    select
        q.Id,
        q.Title,
        q.Tags,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.AcceptedAnswerId,
        ua.AnswerCount,
        ua.AvgScore,
        ua.TotalScore,
        ua.LastAnswerDate,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.LatestBadgeDate,
        u.Reputation,
        u.CreationDate as UserCreation,
        u.DisplayName,
        u.Location,
        case 
            when q.ClosedDate is not null then 'Closed' 
            else 'Open' 
        end as PostStatus
    from Posts q
    left join TopAnswerers ua on q.OwnerUserId = ua.OwnerUserId
    left join UserBadgesStats ub on q.OwnerUserId = ub.UserId
    left join Users u on q.OwnerUserId = u.Id
    where q.PostTypeId = 1
),
QuestionsWithComments as (
    select
        qd.*,
        c.CommentCount,
        string_agg(distinct c.Text, ' ||| ' order by c.CreationDate) as AllComments
    from QuestionDetails qd
    left join (
        select
            PostId,
            count(*) as CommentCount,
            Text,
            CreationDate
        from Comments
        group by PostId, Text, CreationDate
    ) c on qd.Id = c.PostId
    group by qd.Id, qd.Title, qd.Tags, qd.OwnerUserId, qd.Score, qd.ViewCount, qd.CreationDate, qd.AcceptedAnswerId,
             qd.AnswerCount, qd.AvgScore, qd.TotalScore, qd.LastAnswerDate, qd.GoldBadges, qd.SilverBadges, qd.BronzeBadges,
             qd.LatestBadgeDate, qd.Reputation, qd.UserCreation, qd.DisplayName, qd.Location, qd.PostStatus, c.CommentCount
),
PostHistoryCloseReasonsCount as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseVotesCount,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenVotesCount,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as LatestCloseReasonId
    from PostHistory ph
    group by ph.PostId
),
FinalResult as (
    select
        qwc.Id as QuestionId,
        qwc.Title,
        qwc.OwnerUserId,
        coalesce(qwc.DisplayName, 'Anonymous') as UserName,
        qwc.Reputation,
        qwc.GoldBadges,
        qwc.SilverBadges,
        qwc.BronzeBadges,
        qwc.AnswerCount,
        qwc.AvgScore,
        qwc.TotalScore,
        qwc.Score as QuestionScore,
        qwc.ViewCount,
        qwc.CommentCount,
        qwc.AllComments,
        qwc.PostStatus,
        phcrc.CloseVotesCount,
        phcrc.ReopenVotesCount,
        crt.Name as CloseReasonName,
        case when qwc.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        dense_rank() over (partition by qwc.PostStatus order by qwc.Score desc, qwc.ViewCount desc) as RankWithinStatus,
        substring(qwc.Tags from '<([^>]+)>') as PrimaryTag,
        length(qwc.Title) - length(replace(qwc.Title, ' ', '')) + 1 as TitleWordCount,
        case 
            when qwc.ViewCount > 10000 then 'HighTraffic'
            when qwc.ViewCount between 1000 and 10000 then 'MediumTraffic'
            else 'LowTraffic'
        end as TrafficCategory
    from QuestionsWithComments qwc
    left join PostHistoryCloseReasonsCount phcrc on qwc.Id = phcrc.PostId
    left join CloseReasonTypes crt on cast(phcrc.LatestCloseReasonId as int) = crt.Id
)
select
    fr.QuestionId,
    fr.Title,
    fr.UserName,
    fr.Reputation,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.AnswerCount,
    round(fr.AvgScore::numeric, 2) as AvgAnswerScore,
    fr.TotalScore,
    fr.QuestionScore,
    fr.ViewCount,
    fr.CommentCount,
    left(fr.AllComments, 200) || '...' as SampleComments,
    fr.PostStatus,
    fr.CloseVotesCount,
    fr.ReopenVotesCount,
    fr.CloseReasonName,
    fr.HasAcceptedAnswer,
    fr.RankWithinStatus,
    fr.PrimaryTag,
    fr.TitleWordCount,
    fr.TrafficCategory
from FinalResult fr
where fr.AnswerCount >= 5 
  and (fr.GoldBadges + fr.SilverBadges + fr.BronzeBadges) > 0
  and fr.Reputation > 1000
  and (fr.PostStatus = 'Open' or (fr.PostStatus = 'Closed' and fr.CloseVotesCount > 2))
order by fr.TrafficCategory desc, fr.RankWithinStatus, fr.ViewCount desc, fr.QuestionScore desc
limit 100;