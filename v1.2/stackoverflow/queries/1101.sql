with TopBadgedUsers as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        row_number() over (order by count(b.Id) desc, u.Reputation desc) as rn
    from
        Users u
        left join Badges b on u.Id = b.UserId
    group by
        u.Id, u.DisplayName, u.Reputation
    having
        count(b.Id) > 10
), UserQuestionAnswerStats as (
    select
        p.OwnerUserId as UserId,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        avg(case when p.PostTypeId in (1,2) then p.Score else null end) as AvgPostScore,
        max(case when p.PostTypeId in (1,2) then p.Score else null end) as MaxPostScore,
        sum(case when p.PostTypeId = 1 and p.AcceptedAnswerId is not null then 1 else 0 end) as QuestionsWithAcceptedAnswer
    from
        Posts p
    where
        p.OwnerUserId is not null
    group by
        p.OwnerUserId
), UserCloseAndVotes as (
    select
        ph.UserId,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotesCast,
        sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenVotesCast,
        coalesce(closedStats.ClosedPostCount, 0) as PostsClosedCount,
        coalesce(upVotes.ReceivedUpVotes, 0) as ReceivedUpVotes,
        coalesce(downVotes.ReceivedDownVotes, 0) as ReceivedDownVotes
    from
        PostHistory ph
        left join (
            select
                p.OwnerUserId,
                count(1) as ClosedPostCount
            from
                Posts p
            where
                p.ClosedDate is not null and p.PostTypeId = 1
            group by
                p.OwnerUserId
        ) closedStats on ph.UserId = closedStats.OwnerUserId
        left join (
            select
                p.OwnerUserId,
                count(v.Id) as ReceivedUpVotes
            from
                Votes v
                join Posts p on v.PostId = p.Id
            where
                v.VoteTypeId = 2
            group by
                p.OwnerUserId
        ) upVotes on ph.UserId = upVotes.OwnerUserId
        left join (
            select
                p.OwnerUserId,
                count(v.Id) as ReceivedDownVotes
            from
                Votes v
                join Posts p on v.PostId = p.Id
            where
                v.VoteTypeId = 3
            group by
                p.OwnerUserId
        ) downVotes on ph.UserId = downVotes.OwnerUserId
    group by
        ph.UserId,
        closedStats.ClosedPostCount,
        upVotes.ReceivedUpVotes,
        downVotes.ReceivedDownVotes
), ActivityRankings as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(qus.QuestionsCount, 0) as QuestionsCount,
        coalesce(qus.AnswersCount, 0) as AnswersCount,
        coalesce(qus.AvgPostScore, 0) as AvgPostScore,
        coalesce(qus.MaxPostScore, 0) as MaxPostScore,
        coalesce(qus.QuestionsWithAcceptedAnswer, 0) as QuestionsWithAccepted,
        coalesce(ucv.CloseVotesCast, 0) as CloseVotesCast,
        coalesce(ucv.ReopenVotesCast, 0) as ReopenVotesCast,
        coalesce(ucv.PostsClosedCount, 0) as PostsClosedCount,
        coalesce(ucv.ReceivedUpVotes, 0) as ReceivedUpVotes,
        coalesce(ucv.ReceivedDownVotes, 0) as ReceivedDownVotes,
        tbu.BadgeCount,
        tbu.GoldBadges,
        tbu.SilverBadges,
        tbu.BronzeBadges
    from
        Users u
        left join UserQuestionAnswerStats qus on u.Id = qus.UserId
        left join UserCloseAndVotes ucv on u.Id = ucv.UserId
        left join TopBadgedUsers tbu on u.Id = tbu.UserId
    where
        u.Reputation > 500
), RankedUsers as (
    select
        ar.*,
        rank() over (
            order by 
                ar.BadgeCount desc,
                ar.Reputation desc, 
                (ar.QuestionsCount + ar.AnswersCount) desc
        ) as UserRank
    from ActivityRankings ar
), UserCommentsCount as (
    select UserId, count(Id) as CommentCount
    from Comments
    group by UserId
), UserTagExpertise as (
    select
        p.OwnerUserId as UserId,
        tmpl.TagName,
        count(*) as PostsWithTag,
        sum(p.Score) as ScoreSum,
        row_number() over (partition by p.OwnerUserId order by sum(p.Score) desc) as TagRank
    from
        Posts p
        join lateral (
            select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
        ) tmpl on true
    where
        p.PostTypeId = 1 and p.OwnerUserId is not null
    group by
        p.OwnerUserId, tmpl.TagName
    having
        count(*) > 5
), TopUserTags as (
    select UserId, TagName, PostsWithTag, ScoreSum
    from UserTagExpertise
    where TagRank <= 3
)
select
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.BadgeCount,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.QuestionsCount,
    ru.AnswersCount,
    ru.AvgPostScore,
    ru.MaxPostScore,
    ru.QuestionsWithAccepted,
    ru.CloseVotesCast,
    ru.ReopenVotesCast,
    ru.PostsClosedCount,
    ru.ReceivedUpVotes,
    ru.ReceivedDownVotes,
    coalesce(uc.CommentCount, 0) as TotalComments,
    string_agg(distinct (tut.TagName || ':' || cast(tut.PostsWithTag as varchar) || '(' || cast(tut.ScoreSum as varchar) || ')'), ', ') as TopTags,
    case
        when ru.PostsClosedCount = 0 then 'Good standing'
        when ru.PostsClosedCount > 10 then 'High closure'
        else 'Moderate closure'
    end as ClosureStatus,
    greatest(ru.GoldBadges * 3 + ru.SilverBadges * 2 + ru.BronzeBadges, 0) * (1 + ru.AvgPostScore / nullif(ru.MaxPostScore,0)) as InfluenceScore
from
    RankedUsers ru
    left join UserCommentsCount uc on ru.UserId = uc.UserId
    left join TopUserTags tut on ru.UserId = tut.UserId
where
    ru.UserRank <= 100
group by
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.BadgeCount,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.QuestionsCount,
    ru.AnswersCount,
    ru.AvgPostScore,
    ru.MaxPostScore,
    ru.QuestionsWithAccepted,
    ru.CloseVotesCast,
    ru.ReopenVotesCast,
    ru.PostsClosedCount,
    ru.ReceivedUpVotes,
    ru.ReceivedDownVotes,
    uc.CommentCount,
    ClosureStatus
order by
    InfluenceScore desc,
    ru.Reputation desc,
    ru.BadgeCount desc
limit 50;