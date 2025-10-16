-- {"query": "1106.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1481} 
with recursive UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        coalesce(p.AnswerCount,0) as AnswerCount,
        p.FavoriteCount,
        p.Tags,
        -- Calculate tag count considering XML-like tag format: <tag1><tag2>...
        array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><'),1) as TagCount
    from Posts p
    where p.PostTypeId = 1
),
LatestAnswerScores as (
    select
        a.ParentId as QuestionId,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        count(*) as TotalAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
TopVoters as (
    select
        v.PostId,
        count(*) as VoteCount,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
PostActivityChanges as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastActivityChange,
        count(*) as EditCount,
        bool_or(ph.PostHistoryTypeId in (10,11,12,13)) as HasClosureOrDeletion,
        string_agg(distinct pht.Name, ',') as HistoryTypesInvolved
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    group by ph.PostId
),
QuestionWithActivities as (
    select
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.CreationDate,
        q.AnswerCount,
        q.FavoriteCount,
        q.Tags,
        q.TagCount,
        la.AvgAnswerScore,
        la.MaxAnswerScore,
        coalesce(tv.VoteCount, 0) as TotalVotes,
        coalesce(tv.UpVotes, 0) as UpVotes,
        coalesce(tv.DownVotes, 0) as DownVotes,
        pac.LastActivityChange,
        pac.EditCount,
        pac.HasClosureOrDeletion,
        pac.HistoryTypesInvolved
    from QuestionStats q
    left join LatestAnswerScores la on la.QuestionId = q.QuestionId
    left join TopVoters tv on tv.PostId = q.QuestionId
    left join PostActivityChanges pac on pac.PostId = q.QuestionId
),
RankedQuestions as (
    select
        *,
        row_number() over (
            partition by coalesce(array_length(string_to_array(substring(Tags from 2 for length(Tags) - 2), '><'), 1),0)
            order by Score desc, ViewCount desc, AnswerCount desc
        ) as TagRank
    from QuestionWithActivities
),
DuplicatedPosts as (
    select
        pl.PostId,
        count(pl.Id) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    group by pl.PostId
),
OwnerDetails as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        coalesce(ubc.GoldBadges,0) as GoldBadges,
        coalesce(ubc.SilverBadges,0) as SilverBadges,
        coalesce(ubc.BronzeBadges,0) as BronzeBadges
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
),
FinalJoin as (
    select
        rq.*,
        dd.DuplicateCount,
        od.Reputation,
        od.GoldBadges,
        od.SilverBadges,
        od.BronzeBadges
    from RankedQuestions rq
    left join DuplicatedPosts dd on dd.PostId = rq.QuestionId
    left join OwnerDetails od on od.UserId = rq.OwnerUserId
    where rq.TagRank <= 3 -- top 3 questions per tag count group
)
select
    QuestionId,
    Title,
    substring(Title, 1, 50) || case when length(Title) > 50 then '...' else '' end as ShortTitlePreview,
    OwnerUserId,
    Reputation as OwnerReputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    Score,
    ViewCount,
    AnswerCount,
    FavoriteCount,
    TagCount,
    Tags,
    AvgAnswerScore,
    MaxAnswerScore,
    TotalVotes,
    UpVotes,
    DownVotes,
    DuplicateCount,
    LastActivityChange,
    EditCount,
    HasClosureOrDeletion,
    HistoryTypesInvolved,
    CreationDate,
    dense_rank() over (order by Score desc nulls last, ViewCount desc nulls last) as PopularityRank,
    -- Complex string expression showing tags in uppercase separated by commas
    array_to_string(array_agg(distinct upper(trim(tag))), ', ') as UpperTagList,
    -- A complicated conditional expression for activity level
    case
        when EditCount > 10 then 'Highly Edited'
        when EditCount between 5 and 10 then 'Moderately Edited'
        when EditCount between 1 and 4 then 'Lightly Edited'
        else 'Never Edited'
    end as EditIntensity,
    -- NULL logic for detecting stale popular questions
    case 
        when ViewCount > 10000 and LastActivityChange < now() - interval '180 days' then 'Stale Popular Question'
        when ViewCount > 10000 and LastActivityChange >= now() - interval '180 days' then 'Active Popular Question'
        else 'Normal'
    end as ActivityStatus
from FinalJoin fj
-- correlate to unnest tags array for aggregation
left join lateral (
    select unnest(string_to_array(substring(fj.Tags from 2 for length(fj.Tags) - 2), '><')) as tag
) tag_table on true
order by PopularityRank
limit 50;