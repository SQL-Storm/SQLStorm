-- {"query": "2709.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1521} 
with recursive UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
RecentAcceptedAnswers as (
    select distinct p.OwnerUserId,
        p.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.Body
    from Posts p
    join Posts a on p.AcceptedAnswerId = a.Id
    where p.PostTypeId = 1 and a.PostTypeId = 2 and p.AcceptedAnswerId is not null
),
TopScoringQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) rn
    from Posts p
    where p.PostTypeId = 1 and p.Score is not null
),
UserTopQuestions as (
    select
        tq.Id,
        tq.Title,
        tq.OwnerUserId,
        tq.Score,
        tq.CreationDate,
        tq.Tags
    from TopScoringQuestions tq
    where tq.rn <= 3
),
QuestionCommentsCount as (
    select
        c.PostId,
        count(c.Id) as CommentsCount
    from Comments c
    group by c.PostId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10 and ph.PostId is not null
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when p.PostTypeId = 1 then 1 else 0 end),0) as QuestionCount,
        coalesce(sum(case when p.PostTypeId = 2 then 1 else 0 end),0) as AnswerCount,
        coalesce(sum(vt.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt.DownVotes),0) as TotalDownVotes,
        max(p.LastActivityDate) as LastActivity,
        count(distinct ph.PostId) as PostsEdited
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Votes v on p.Id = v.PostId
    left join (
        select
            v.PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by v.PostId
    ) vt on p.Id = vt.PostId
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName
),
UserTagsAgg as (
    select
        OwnerUserId,
        unnest(string_to_array(regexp_replace(Tags, '[<>]', '', 'g'), ',')) as Tag
    from Posts
    where PostTypeId = 1 and Tags is not null
),
TagPopularity as (
    select
        Tag,
        count(*) as QuestionCount,
        avg(Score) as AverageScore
    from UserTagsAgg
    join Posts p on UserTagsAgg.OwnerUserId = p.OwnerUserId
        and p.PostTypeId = 1
    group by Tag
),
UserTagRanks as (
    select
        OwnerUserId as UserId,
        Tag,
        rank() over (partition by OwnerUserId order by count(*) desc) as TagRank
    from UserTagsAgg
    group by OwnerUserId, Tag
),
DistinctUserTags as (
    select UserId, Tag
    from UserTagRanks
    where TagRank <= 2
),
AnswerScoresWithRanks as (
    select a.Id, a.ParentId, a.Score, a.CreationDate,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
TopAnswerPerQuestion as (
    select Id, ParentId, Score, CreationDate
    from AnswerScoresWithRanks
    where AnswerRank = 1
),
UserQuestionAnswerStats as (
    select
        q.OwnerUserId as QuestionOwner,
        count(distinct a.Id) as NumAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        count(case when a.Score > q.Score then 1 end) as AnswersBetterThanQuestionScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.OwnerUserId
)
select
    u.Id as UserId,
    u.DisplayName,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalUpVotes,
    uas.TotalDownVotes,
    uas.LastActivity,
    uas.PostsEdited,
    us.AnswersBetterThanQuestionScore,
    us.AvgAnswerScore,
    us.MaxAnswerScore,
    string_agg(distinct dt.Tag, ', ') as TopTags,
    rq.AcceptedAnswerId,
    rq.AcceptedAnswerScore,
    rq.AnswerCreationDate,
    substring(rq.Body from 1 for 100) as AcceptedAnswerSnippet
from Users u
left join UserBadgeCounts ubc on u.Id = ubc.UserId
left join UserActivitySummary uas on u.Id = uas.UserId
left join UserQuestionAnswerStats us on u.Id = us.QuestionOwner
left join DistinctUserTags dt on u.Id = dt.UserId
left join RecentAcceptedAnswers rq on u.Id = rq.OwnerUserId
where u.Reputation > 1000
group by
    u.Id, u.DisplayName, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges,
    uas.QuestionCount, uas.AnswerCount, uas.TotalUpVotes, uas.TotalDownVotes, uas.LastActivity, uas.PostsEdited,
    us.AnswersBetterThanQuestionScore, us.AvgAnswerScore, us.MaxAnswerScore,
    rq.AcceptedAnswerId, rq.AcceptedAnswerScore, rq.AnswerCreationDate, rq.Body
order by uas.TotalUpVotes desc nulls last, uas.QuestionCount desc nulls last
limit 50;