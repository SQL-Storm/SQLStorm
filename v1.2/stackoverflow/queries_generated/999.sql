-- {"query": "999.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1630} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(b.Id) as BadgeCount,
        row_number() over (partition by u.Location order by u.Reputation desc nulls last) as LocationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    where u.Location is not null
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
), TopUsersByLocation as (
    select UserId, DisplayName, Reputation, Location, QuestionCount, AnswerCount, BadgeCount
    from RecursiveUserActivity
    where LocationRank <= 5
), PostVotesSummary as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as UpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as DownVotes,
        coalesce(sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end), 0) as TotalBounty,
        count(distinct c.Id) as CommentCount
    from Posts p
    left join Votes v on v.PostId = p.Id
    left join Comments c on c.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score
), PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.OwnerUserId as QuestionOwner,
        q.Score as QuestionScore,
        coalesce(a.AnswerCount,0) as AnswerCount,
        coalesce(avg(a.AnswerScore),0) as AvgAnswerScore,
        coalesce(max(a.AnswerScore),0) as MaxAnswerScore,
        coalesce(min(a.AnswerScore),0) as MinAnswerScore,
        q.Tags,
        q.ClosedDate
    from Posts q
    left join (
        select
            p.ParentId,
            count(*) as AnswerCount,
            avg(p.Score) as AnswerScore,
            max(p.Score) as MaxAnswerScore,
            min(p.Score) as MinAnswerScore
        from Posts p
        where p.PostTypeId = 2
        group by p.ParentId
    ) a on a.ParentId = q.Id
    where q.PostTypeId = 1
), DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate as LinkDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
), CloseReasonsCount as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null and ph.Comment ~ '^\d+$'
    group by ph.PostId, crt.Name
), UserBadgesPerClass as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
), UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(ps.QuestionCount,0) as QuestionsPosted,
        coalesce(ps.AnswerCount,0) as AnswersPosted,
        coalesce(bc.GoldBadges,0) as GoldBadges,
        coalesce(bc.SilverBadges,0) as SilverBadges,
        coalesce(bc.BronzeBadges,0) as BronzeBadges,
        case when u.Location is not null then u.Location else 'Unknown' end as Location,
        coalesce(sum(v.UpVotes),0) as TotalUpVotes,
        coalesce(sum(v.DownVotes),0) as TotalDownVotes,
        coalesce(sum(v.TotalBounty),0) as TotalBountyEarned
    from Users u
    left join (
        select
            OwnerUserId,
            count(case when PostTypeId=1 then 1 end) as QuestionCount,
            count(case when PostTypeId=2 then 1 end) as AnswerCount
        from Posts
        group by OwnerUserId
    ) ps on ps.OwnerUserId = u.Id
    left join UserBadgesPerClass bc on bc.UserId = u.Id
    left join PostVotesSummary v on v.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges, u.Location, ps.QuestionCount, ps.AnswerCount
), RankedQuestionsWithDuplicates as (
    select
        pas.QuestionId,
        pas.Title,
        pas.QuestionOwner,
        pas.QuestionScore,
        pas.AnswerCount,
        pas.AvgAnswerScore,
        pas.MaxAnswerScore,
        pas.MinAnswerScore,
        pas.Tags,
        pas.ClosedDate,
        coalesce(dl.RelatedPostId, 0) as DuplicateOf,
        row_number() over (partition by pas.QuestionOwner order by pas.Score desc) as UserQuestionRank
    from PostAnswerStats pas
    left join DuplicateLinks dl on dl.PostId = pas.QuestionId
    where pas.ClosedDate is null
), UserTopActiveQuestions as (
    select
        uas.UserId,
        uas.DisplayName,
        rqd.QuestionId,
        rqd.Title,
        rqd.AnswerCount,
        rqd.AvgAnswerScore,
        rqd.DuplicateOf,
        rqd.UserQuestionRank
    from UserActivitySummary uas
    join RankedQuestionsWithDuplicates rqd on rqd.QuestionOwner = uas.UserId
    where rqd.UserQuestionRank <= 3
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.QuestionsPosted,
    u.AnswersPosted,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.TotalUpVotes,
    u.TotalDownVotes,
    u.TotalBountyEarned,
    uq.QuestionId,
    uq.Title,
    uq.AnswerCount,
    round(uq.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    case when uq.DuplicateOf = 0 then null else uq.DuplicateOf end as DuplicateOfQuestionId
from UserActivitySummary u
left join UserTopActiveQuestions uq on uq.UserId = u.UserId
where u.Reputation > 1000
order by u.TotalUpVotes desc, uq.AnswerCount desc, u.UserId
limit 100;