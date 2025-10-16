-- {"query": "297.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1921} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date is not null
),
TopBadges as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where rn <= 3
),
QuestionStats as (
    select 
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 1 and p.AcceptedAnswerId is not null) as AcceptedQuestions,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        max(p.ViewCount) filter (where p.PostTypeId = 1) as MaxQuestionViews,
        string_agg(distinct substring(t.TagName from 1 for 10), ', ') as SampleTags
    from Posts p
    left join LATERAL (
        select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as TagName
    ) t on true
    where p.OwnerUserId is not null and p.PostTypeId = 1
    group by p.OwnerUserId
),
AnswerStats as (
    select 
        p.OwnerUserId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        sum(case when p.ParentId is not null and p.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswersCount
    from Posts p
    left join Posts q on p.ParentId = q.Id and q.PostTypeId = 1
    where p.OwnerUserId is not null and p.PostTypeId = 2
    group by p.OwnerUserId
),
UserActivity as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(qs.QuestionCount,0) as QuestionCount,
        coalesce(qs.AcceptedQuestions,0) as AcceptedQuestions,
        coalesce(qs.AvgQuestionScore,0) as AvgQuestionScore,
        coalesce(qs.MaxQuestionViews,0) as MaxQuestionViews,
        coalesce(asn.AnswerCount,0) as AnswerCount,
        coalesce(asn.AvgAnswerScore,0) as AvgAnswerScore,
        coalesce(asn.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(asn.AcceptedAnswersCount,0) as AcceptedAnswersCount
    from Users u
    left join QuestionStats qs on u.Id = qs.OwnerUserId
    left join AnswerStats asn on u.Id = asn.OwnerUserId
),
UserVoteSummary as (
    select 
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesCast,
        count(*) filter (where vt.Name = 'BountyStart') as BountiesStarted,
        count(*) filter (where vt.Name = 'BountyClose') as BountiesClosed
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    where v.UserId is not null
    group by v.UserId
),
UserCommentStats as (
    select 
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        max(c.Score) as MaxCommentScore
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
UserPostHistoryEdits as (
    select 
        ph.UserId,
        count(distinct ph.PostId) as EditedPostsCount,
        count(*) as TotalEdits,
        count(distinct ph.PostHistoryTypeId) as DistinctEditTypes
    from PostHistory ph
    where ph.UserId is not null
    group by ph.UserId
),
UserAggregated as (
    select 
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastAccessDate,
        ua.QuestionCount,
        ua.AcceptedQuestions,
        ua.AvgQuestionScore,
        ua.MaxQuestionViews,
        ua.AnswerCount,
        ua.AvgAnswerScore,
        ua.MaxAnswerScore,
        ua.AcceptedAnswersCount,
        coalesce(uvs.UpVotesCast,0) as UpVotesCast,
        coalesce(uvs.DownVotesCast,0) as DownVotesCast,
        coalesce(uvs.FavoritesCast,0) as FavoritesCast,
        coalesce(uvs.BountiesStarted,0) as BountiesStarted,
        coalesce(uvs.BountiesClosed,0) as BountiesClosed,
        coalesce(ucs.CommentCount,0) as CommentCount,
        coalesce(ucs.AvgCommentLength,0) as AvgCommentLength,
        coalesce(ucs.MaxCommentScore,0) as MaxCommentScore,
        coalesce(uph.EditedPostsCount,0) as EditedPostsCount,
        coalesce(uph.TotalEdits,0) as TotalEdits,
        coalesce(uph.DistinctEditTypes,0) as DistinctEditTypes
    from UserActivity ua
    left join UserVoteSummary uvs on ua.Id = uvs.UserId
    left join UserCommentStats ucs on ua.Id = ucs.UserId
    left join UserPostHistoryEdits uph on ua.Id = uph.UserId
),
RankedUsers as (
    select 
        *,
        rank() over (order by Reputation desc, QuestionCount desc, AnswerCount desc) as ReputationRank,
        dense_rank() over (order by QuestionCount desc) as QuestionRank,
        dense_rank() over (order by AnswerCount desc) as AnswerRank,
        ntile(4) over (order by Reputation desc) as ReputationQuartile
    from UserAggregated
),
FilteredUsers as (
    select * from RankedUsers
    where ReputationRank <= 1000 and QuestionCount > 0
),
UserDuplicates as (
    select 
        p.Id as PostId,
        p.OwnerUserId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount
    from Posts p
    join PostLinks pl on p.Id = pl.PostId
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where p.PostTypeId = 1 and pl.LinkTypeId = 3
),
UserDuplicateCounts as (
    select 
        OwnerUserId,
        count(distinct PostId) as DuplicateQuestionsCount,
        count(distinct RelatedPostId) as DuplicateTargetsCount
    from UserDuplicates
    group by OwnerUserId
)
select 
    fu.Id as UserId,
    fu.DisplayName,
    fu.Reputation,
    fu.ReputationRank,
    fu.ReputationQuartile,
    fu.QuestionCount,
    fu.AcceptedQuestions,
    round(fu.AvgQuestionScore::numeric,2) as AvgQuestionScore,
    fu.MaxQuestionViews,
    fu.AnswerCount,
    round(fu.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    fu.MaxAnswerScore,
    fu.AcceptedAnswersCount,
    fu.UpVotesCast,
    fu.DownVotesCast,
    fu.FavoritesCast,
    fu.BountiesStarted,
    fu.BountiesClosed,
    fu.CommentCount,
    round(fu.AvgCommentLength::numeric,2) as AvgCommentLength,
    fu.MaxCommentScore,
    fu.EditedPostsCount,
    fu.TotalEdits,
    fu.DistinctEditTypes,
    coalesce(udc.DuplicateQuestionsCount,0) as DuplicateQuestionsCount,
    coalesce(udc.DuplicateTargetsCount,0) as DuplicateTargetsCount,
    tb.BadgeName,
    case 
        when fu.Reputation > 100000 then 'Legendary'
        when fu.Reputation > 50000 then 'Expert'
        when fu.Reputation > 10000 then 'Intermediate'
        else 'Beginner'
    end as UserLevel,
    concat_ws(' | ', 
        coalesce(tb.BadgeName, 'No Badge'),
        'Rep: ' || fu.Reputation,
        'Q: ' || fu.QuestionCount,
        'A: ' || fu.AnswerCount,
        'Comments: ' || fu.CommentCount
    ) as Summary
from FilteredUsers fu
left join UserDuplicateCounts udc on fu.Id = udc.OwnerUserId
left join TopBadges tb on fu.Id = tb.UserId
order by fu.ReputationRank
limit 100;