-- {"query": "2667.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1614} 
with recursive UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by max(b.Date) desc nulls last) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopUsersWithBadgeRatio as (
    select
        UserId,
        DisplayName,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        case when GoldBadges + SilverBadges + BronzeBadges > 0 
             then (1.0 * GoldBadges + 0.5 * SilverBadges + 0.1 * BronzeBadges) / nullif((GoldBadges + SilverBadges + BronzeBadges),0)
             else 0 end as WeightedBadgeRatio,
        rn
    from UserBadgeCounts
    where rn <= 100
),
RecentHighlyVotedQuestions as (
    select p.Id, p.Title, p.OwnerUserId, p.Score, p.CreationDate, p.Tags,
      row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as rn
    from Posts p
    where p.PostTypeId = 1 -- questions
      and p.CreationDate >= current_date - interval '1 year'
      and p.Score > 5
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct a.Id) filter (where a.PostTypeId = 2) as AnswersGiven,
        coalesce(sum(v.CountUpVotes),0) as TotalUpVotes,
        coalesce(sum(v.CountDownVotes),0) as TotalDownVotes,
        max(ubcr.WeightedBadgeRatio) as BadgeRatio
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join (
        select
            p.OwnerUserId,
            p.Id,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as CountUpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as CountDownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId, p.Id
    ) v on v.OwnerUserId = u.Id
    left join TopUsersWithBadgeRatio ubcr on ubcr.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionAnswerLinkAnalysis as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        count(distinct a.Id) as AnswerCount,
        count(distinct pl.Id) filter (where pl.LinkTypeId = 3) as DuplicateLinkCount,
        sum(case when a.Score > q.Score then 1 else 0 end) as AnswersWithHigherScoreThanQuestion
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join PostLinks pl on pl.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.OwnerUserId
),
TagPopularity as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as Tag,
        count(*) as QuestionCount,
        avg(p.Score) as AvgScore
    from Posts p
    where p.PostTypeId = 1
    group by Tag
    having count(*) > 100
),
HighlyVotedAnswerDetails as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.Score as AnswerScore,
        q.Score as QuestionScore,
        row_number() over (partition by a.ParentId order by a.Score desc) as AnswerRank,
        (select count(*) from Comments c where c.PostId = a.Id and c.UserId = a.OwnerUserId) as AuthorCommentCount
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2 and a.Score > 10
),
ComplexUserEngagement as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as NumPosts,
        sum(case when p.PostTypeId=1 then p.ViewCount else 0 end) as TotalViewsOnQuestions,
        sum(case when p.PostTypeId=2 then vCount.UpVotes else 0 end) as TotalUpVotesOnAnswers,
        max(vCount.UpVotes) filter (where p.PostTypeId = 2) as MaxUpVotesOnSingleAnswer,
        avg(length(p.Body)) as AvgBodyLength,
        (select count(*) from Comments c where c.UserId = u.Id) as TotalCommentsMade
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            PostId,
            sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes
        from Votes
        group by PostId
    ) vCount on vCount.PostId = p.Id
    group by u.Id, u.DisplayName
)
select 
    uas.UserId,
    uas.DisplayName,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.TotalUpVotes,
    uas.TotalDownVotes,
    coalesce(uas.BadgeRatio,0) as BadgeWeightedRatio,
    qal.AnswerCount,
    qal.DuplicateLinkCount,
    qal.AnswersWithHigherScoreThanQuestion,
    coalesce(tp.Tag, 'NoTags') as PopularTag,
    tp.QuestionCount as PopularTagQuestionCount,
    tp.AvgScore as PopularTagAverageScore,
    ha.AnswerRank,
    ha.AnswerScore,
    ha.QuestionScore,
    ha.AuthorCommentCount,
    cue.TotalViewsOnQuestions,
    cue.TotalUpVotesOnAnswers,
    cue.MaxUpVotesOnSingleAnswer,
    cue.AvgBodyLength,
    cue.TotalCommentsMade
from UserActivitySummary uas
left join QuestionAnswerLinkAnalysis qal on qal.QuestionId = (select min(Id) from Posts p where p.OwnerUserId = uas.UserId and p.PostTypeId = 1)
left join HighlyVotedAnswerDetails ha on ha.AnswerOwnerUserId = uas.UserId
left join TagPopularity tp on tp.Tag = (
    select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))
    from Posts p
    where p.OwnerUserId = uas.UserId and p.PostTypeId = 1
    order by p.Score desc nulls last limit 1
)
left join ComplexUserEngagement cue on cue.UserId = uas.UserId
where uas.QuestionsAsked > 10 or uas.AnswersGiven > 20
order by uas.TotalUpVotes desc
limit 100;