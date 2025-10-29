-- {"query": "2976.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1473} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, array[t.TagName] as AncestorTags
    from Tags t
    where t.IsRequired = 1
    union all
    select child.Id, child.TagName, child.Count, parent.AncestorTags || child.TagName
    from Tags child
    join RecursiveTagHierarchy parent
        on child.Id <> parent.Id
       and child.Count < parent.Count
       and not child.TagName = any(parent.AncestorTags)
    where child.IsRequired = 0
),
UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter(where b.Class = 1) as GoldBadges,
        count(b.Id) filter(where b.Class = 2) as SilverBadges,
        count(b.Id) filter(where b.Class = 3) as BronzeBadges,
        rank() over (order by count(b.Id) desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopAnsweredQuestions as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.OwnerUserId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
      and q.Score >= 10
      and a.Score is not null
),
QuestionCloseInfo as (
    select
        ph.PostId,
        min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as FirstCloseDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as LastReopenDate,
        string_agg(distinct crt.Name, ', ' order by crt.Name) as CloseReasons
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
AnswerVotesSummary as (
    select
        a.Id as AnswerId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        count(v.Id) as TotalVotes,
        avg(case when v.VoteTypeId in (2,3) then 1 else null end) as VoteRatio
    from Posts a
    left join Votes v on v.PostId = a.Id
    where a.PostTypeId = 2
    group by a.Id
),
ComplexPostsAnalysis as (
    select
        q.QuestionId,
        q.Title,
        q.CreationDate,
        q.QuestionScore,
        q.ViewCount,
        q.OwnerUserId,
        u.DisplayName as QuestionOwner,
        ab.AnswerId,
        ab.AnswerScore,
        au.DisplayName as AnswerOwner,
        avs.UpVotes,
        avs.DownVotes,
        avs.TotalVotes,
        avs.VoteRatio,
        q.AnswerRank,
        q.QuestionScore * coalesce(avs.VoteRatio,0) as CompositeScore,
        close.FirstCloseDate,
        close.LastReopenDate,
        close.CloseReasons,
        array_to_string(
            array(
                select distinct unnest(string_to_array(coalesce(p.Tags,''),'><'))
            ), ', '
        ) as TagsExtracted,
        phc.RevisionCount,
        phc.LastEditDate,
        pb.GoldBadges,
        pb.SilverBadges,
        pb.BronzeBadges,
        pb.BadgeRank
    from TopAnsweredQuestions q
    left join Users u on u.Id = q.OwnerUserId
    left join Posts ab on ab.Id = q.AnswerId
    left join Users au on au.Id = ab.OwnerUserId
    left join AnswerVotesSummary avs on avs.AnswerId = ab.Id
    left join QuestionCloseInfo close on close.PostId = q.QuestionId
    left join (
        select PostId, count(*) as RevisionCount, max(CreationDate) as LastEditDate
        from PostHistory
        group by PostId
    ) phc on phc.PostId = q.QuestionId
    left join UserBadgeCounts pb on pb.UserId = q.OwnerUserId
    left join Posts p on p.Id = q.QuestionId
    where q.AnswerRank = 1
),
OwnersWithUpdates as (
    select distinct ph.UserId
    from PostHistory ph
    where ph.UserId is not null
),
CombinedUserSet as (
    select distinct u.Id from Users u
    union
    select UserId from OwnersWithUpdates
)
select 
    cpa.QuestionId,
    cpa.Title,
    cpa.CreationDate,
    cpa.ViewCount,
    cpa.QuestionScore,
    coalesce(cpa.TagsExtracted, 'No Tags') as TagsList,
    cpa.AnswerId,
    cpa.AnswerScore,
    cpa.UpVotes,
    cpa.DownVotes,
    cpa.TotalVotes,
    round(cpa.CompositeScore::numeric,2) as CompositeScore,
    cpa.FirstCloseDate,
    cpa.LastReopenDate,
    coalesce(cpa.CloseReasons, 'None') as CloseReasons,
    cpa.RevisionCount,
    cpa.LastEditDate,
    cpa.GoldBadges,
    cpa.SilverBadges,
    cpa.BronzeBadges,
    cpa.BadgeRank,
    cpa.QuestionOwner,
    cpa.AnswerOwner,
    concat(
        'User ', cpa.QuestionOwner,
        ' has ', 
        coalesce(cpa.GoldBadges,0), ' gold, ',
        coalesce(cpa.SilverBadges,0), ' silver and ',
        coalesce(cpa.BronzeBadges,0), ' bronze badges.'
    ) as OwnerBadgeSummary,
    case 
        when cpa.FirstCloseDate is not null 
        then 'Closed on ' || to_char(cpa.FirstCloseDate, 'YYYY-MM-DD') || '; Reasons: ' || coalesce(cpa.CloseReasons, 'N/A')
        else 'Never closed'
    end as CloseStatus,
    row_number() over (partition by cpa.QuestionOwner order by cpa.CompositeScore desc) as OwnerTopPostRank
from ComplexPostsAnalysis cpa
where cpa.ViewCount > 5000
order by cpa.CompositeScore desc
limit 100;