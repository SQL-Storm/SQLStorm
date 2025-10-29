-- {"query": "2799.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1430}
with TopUsers as (
    select u.Id, u.DisplayName, u.Reputation,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        row_number() over (order by u.Reputation desc, count(distinct b.Id) desc) as Rnk
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 10000
    group by u.Id, u.DisplayName, u.Reputation
),
UserPostStats as (
    select
        p.OwnerUserId as UserId,
        count(case when p.PostTypeId = 1 then 1 end) as Questions,
        count(case when p.PostTypeId = 2 then 1 end) as Answers,
        count(case when p.PostTypeId = 2 and p.Score > 5 then 1 end) as HighScoreAnswers,
        avg(case when p.PostTypeId in (1, 2) then p.Score end) as AvgPostScore,
        max(p.CreationDate) as LastPostDate
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId <> -1
    group by p.OwnerUserId
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        count(distinct c.PostId) as DistinctPostsCommented
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
ClosedQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as CloseRank
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where p.PostTypeId = 1 and p.ClosedDate is not null
),
UserCloseStats as (
    select
        OwnerUserId,
        count(*) as ClosedQuestionCount,
        string_agg(distinct CloseReasonName, ', ') as UniqueCloseReasons
    from ClosedQuestions
    group by OwnerUserId
),
RecentAcceptedAnswers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.CreationDate as AnswerCreationDate,
        q.AcceptedAnswerId,
        q.Score as QuestionScore,
        a.Score as AnswerScore,
        row_number() over (partition by a.OwnerUserId order by a.CreationDate desc) as RecentAnswerRank
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2 and q.AcceptedAnswerId = a.Id
),
AggregatedVotes as (
    select
        p.OwnerUserId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        count(distinct v.UserId) as VoteUserCount
    from Posts p
    left join Votes v on v.PostId = p.Id
    where p.OwnerUserId is not null and p.OwnerUserId <> -1
    group by p.OwnerUserId
)
select
    tu.Id as UserId,
    tu.DisplayName,
    tu.Reputation,
    coalesce(ups.Questions, 0) as QuestionsPosted,
    coalesce(ups.Answers, 0) as AnswersPosted,
    coalesce(ups.HighScoreAnswers, 0) as HighScoreAnswers,
    round(coalesce(ups.AvgPostScore, 0), 2) as AveragePostScore,
    coalesce(ucs.ClosedQuestionCount, 0) as ClosedQuestions,
    coalesce(ucs.UniqueCloseReasons, 'None') as CloseReasons,
    case when coalesce(ucs.ClosedQuestionCount, 0) > 5 then true else false end as HasManyClosed,
    coalesce(acs.UpVotes,0) as TotalUpVotes,
    coalesce(acs.DownVotes,0) as TotalDownVotes,
    acs.VoteUserCount,
    coalesce(ucs.ClosedQuestionCount, 0) + coalesce(ups.Answers, 0) as PostsPlusClosed,
    tu.BadgeCount,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    coalesce(ucs.ClosedQuestionCount, 0) * 1.0 / nullif(tu.BadgeCount,0) as ClosedPerBadgeRatio,
    raa.AnswerId as LatestAcceptedAnswerId,
    raa.AnswerScore,
    raa.QuestionScore,
    raa.AnswerCreationDate,
    case
        when tu.Reputation > 100000 then 'Legendary'
        when tu.Reputation between 50000 and 100000 then 'Expert'
        else 'Intermediate'
    end as UserLevel,
    substring(tu.DisplayName from 1 for 3) || coalesce(substring(u.Location, 1,3), '') || coalesce(substring(u.WebsiteUrl, 9, 4), '') as UserCode,
    (select count(*) from PostLinks pl where pl.PostId in (
        select Id from Posts where OwnerUserId = tu.Id)) as LinkedPostsCount,
    (
        select
            count(distinct lp.RelatedPostId)
        from PostLinks lp
        join Posts p2 on p2.Id = lp.RelatedPostId
        where p2.OwnerUserId = tu.Id and lp.LinkTypeId = 1
    ) as IncomingLinksCount
from TopUsers tu
left join UserPostStats ups on ups.UserId = tu.Id
left join UserCloseStats ucs on ucs.OwnerUserId = tu.Id
left join AggregatedVotes acs on acs.OwnerUserId = tu.Id
left join RecentAcceptedAnswers raa on raa.OwnerUserId = tu.Id and raa.RecentAnswerRank = 1
left join Users u on u.Id = tu.Id
where tu.Rnk <= 100
order by tu.Reputation desc, tu.BadgeCount desc
limit 50;