-- {"query": "146.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1444} 
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
        count(distinct b.Id) as BadgeCount,
        sum(vt.Name = 'UpMod'::text)::int as TotalUpVotes,
        sum(vt.Name = 'DownMod'::text)::int as TotalDownVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserRankings as (
    select
        UserId,
        DisplayName,
        Reputation,
        QuestionCount,
        AnswerCount,
        CommentCount,
        BadgeCount,
        TotalUpVotes,
        TotalDownVotes,
        row_number() over (order by Reputation desc, QuestionCount desc, AnswerCount desc) as RankByReputation,
        rank() over (partition by BadgeCount order by Reputation desc) as RankWithinBadgeCount
    from RecursiveUserActivity
),
TopUsers as (
    select * from UserRankings where RankByReputation <= 100
),
PostAggregates as (
    select
        p.OwnerUserId as UserId,
        count(*) filter (where p.PostTypeId = 1) as TotalQuestions,
        count(*) filter (where p.PostTypeId = 2) as TotalAnswers,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews,
        bool_or(p.ClosedDate is not null) as HasClosedPosts
    from Posts p
    group by p.OwnerUserId
),
UserActivityWithPosts as (
    select
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.CommentCount,
        tu.BadgeCount,
        tu.TotalUpVotes,
        tu.TotalDownVotes,
        pa.TotalQuestions,
        pa.TotalAnswers,
        pa.AvgPostScore,
        pa.MaxPostScore,
        pa.TotalQuestionViews,
        pa.HasClosedPosts,
        case when pa.HasClosedPosts then 'Yes' else 'No' end as ClosedPostsFlag
    from TopUsers tu
    left join PostAggregates pa on pa.UserId = tu.UserId
),
UserCloseReasons as (
    select
        ph.UserId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 and ph.UserId is not null
    group by ph.UserId, crt.Name
),
UserCloseReasonSummary as (
    select
        UserId,
        string_agg(format('%s (%s)', CloseReason, CloseCount), ', ') as CloseReasonsSummary
    from UserCloseReasons
    group by UserId
),
UserFinalSummary as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.BadgeCount,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.AvgPostScore,
        ua.MaxPostScore,
        ua.TotalQuestionViews,
        ua.ClosedPostsFlag,
        coalesce(ucs.CloseReasonsSummary, 'None') as CloseReasonsSummary,
        dense_rank() over (order by ua.Reputation desc) as ReputationRank,
        ntile(4) over (order by ua.TotalUpVotes desc) as UpVotesQuartile
    from UserActivityWithPosts ua
    left join UserCloseReasonSummary ucs on ucs.UserId = ua.UserId
)
select
    ufs.UserId,
    ufs.DisplayName,
    ufs.Reputation,
    ufs.ReputationRank,
    ufs.QuestionCount,
    ufs.AnswerCount,
    ufs.CommentCount,
    ufs.BadgeCount,
    ufs.TotalUpVotes,
    ufs.TotalDownVotes,
    ufs.TotalQuestions,
    ufs.TotalAnswers,
    round(ufs.AvgPostScore::numeric, 2) as AvgPostScore,
    ufs.MaxPostScore,
    ufs.TotalQuestionViews,
    ufs.ClosedPostsFlag,
    ufs.CloseReasonsSummary,
    ufs.UpVotesQuartile,
    case
        when ufs.Reputation > 100000 then 'Legendary'
        when ufs.Reputation > 50000 then 'Expert'
        when ufs.Reputation > 10000 then 'Intermediate'
        else 'Beginner'
    end as UserLevel,
    concat_ws(' | ',
        coalesce(ufs.DisplayName, 'Unknown'),
        'Rep: ' || ufs.Reputation,
        'Q: ' || ufs.QuestionCount,
        'A: ' || ufs.AnswerCount,
        'Badges: ' || ufs.BadgeCount
    ) as UserSummaryString
from UserFinalSummary ufs
where ufs.BadgeCount > 0
order by ufs.Reputation desc, ufs.TotalUpVotes desc
limit 50

union

select
    null as UserId,
    'Aggregate Totals' as DisplayName,
    sum(Reputation) as Reputation,
    null as ReputationRank,
    sum(QuestionCount) as QuestionCount,
    sum(AnswerCount) as AnswerCount,
    sum(CommentCount) as CommentCount,
    sum(BadgeCount) as BadgeCount,
    sum(TotalUpVotes) as TotalUpVotes,
    sum(TotalDownVotes) as TotalDownVotes,
    sum(TotalQuestions) as TotalQuestions,
    sum(TotalAnswers) as TotalAnswers,
    null as AvgPostScore,
    null as MaxPostScore,
    sum(TotalQuestionViews) as TotalQuestionViews,
    null as ClosedPostsFlag,
    null as CloseReasonsSummary,
    null as UpVotesQuartile,
    null as UserLevel,
    null as UserSummaryString
from UserFinalSummary
where BadgeCount > 0;