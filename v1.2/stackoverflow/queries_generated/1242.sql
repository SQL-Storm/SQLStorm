-- {"query": "1242.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1178} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        array_agg(distinct bh.Name) filter (where bh.Name is not null) as BadgeNames,
        coalesce(u.Views,0) as Views, 
        coalesce(u.UpVotes,0) as UpVotes,
        coalesce(u.DownVotes,0) as DownVotes,
        u.CreationDate,
        row_number() over (partition by u.Id order by u.LastAccessDate desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    left join PostHistoryTypes bh on b.Class::smallint = bh.Id -- purposely mismatched join for complexity; will produce NULL usually
    group by u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
FilteredUsers as (
    select * from RecursiveUserActivity where rn = 1 
    and Reputation > (
        select avg(Reputation) from Users where Reputation > 1000
    )
),
PostsWithTags as (
    select p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.Tags,
        regexp_split_to_table(trim(both '<>' from coalesce(p.Tags,'')), '>|<') as IndividualTag
    from Posts p
    where p.PostTypeId = 1
),
UserTagStats as (
    select
        fu.UserId,
        pt.IndividualTag,
        count(distinct pt.Id) as QuestionCount,
        sum(coalesce(pt.Score,0)) as TotalScore,
        sum(coalesce(pt.ViewCount,0)) as TotalViews,
        rank() over (partition by fu.UserId order by count(distinct pt.Id) desc) as TagRank
    from FilteredUsers fu
    left join PostsWithTags pt on fu.UserId = pt.OwnerUserId
    group by fu.UserId, pt.IndividualTag
),
TopUserTags as (
    select UserId, IndividualTag, QuestionCount, TotalScore, TotalViews
    from UserTagStats
    where TagRank <= 3
),
RecentHotPosts as (
    select p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName as Owner,
      Row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    inner join Users u on p.OwnerUserId = u.Id
    inner join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 52 -- SelectedHotQuestion
    where p.CreationDate > current_date - interval '90 day'
),
VoteSummary as (
    select 
        p.Id as PostId,
        count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
        count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as TotalBounty,
        count(distinct v.UserId) as DistinctVoters
    from Posts p
    left join Votes v on p.Id = v.PostId
    group by p.Id
),
FinalAggregated as (
    select
        f.UserId,
        fu.DisplayName,
        fu.Reputation,
        coalesce(sum(ut.QuestionCount), 0) as TotalQuestionsInTopTags,
        coalesce(sum(ut.TotalScore), 0) as TotalScoreInTopTags,
        coalesce(sum(ut.TotalViews), 0) as TotalViewsInTopTags,
        coalesce(sum(vs.UpVotes),0) as TotalPostUpVotes,
        coalesce(sum(vs.DownVotes),0) as TotalPostDownVotes,
        coalesce(sum(vs.TotalBounty),0) as TotalBountyEarned,
        ft.IndividualTag as SampleTopTag,
        rhp.Title as TopHotQuestionTitle,
        rhp.CreationDate as TopHotQuestionDate,
        rhp.Score as TopHotQuestionScore
    from FilteredUsers fu
    left join TopUserTags ut on fu.UserId = ut.UserId
    left join VoteSummary vs on vs.PostId in (select Id from Posts where OwnerUserId = fu.UserId)
    left join (
        select distinct UserId, IndividualTag from TopUserTags
    ) ft on ft.UserId = fu.UserId
    left join LATERAL (
        select Title, CreationDate, Score
        from RecentHotPosts rhp2
        where rhp2.Owner = fu.DisplayName
        order by Score desc
        limit 1
    ) rhp on true
    group by f.UserId, fu.DisplayName, fu.Reputation, ft.IndividualTag, rhp.Title, rhp.CreationDate, rhp.Score
)
select
    UserId,
    DisplayName,
    Reputation,
    TotalQuestionsInTopTags,
    TotalScoreInTopTags,
    TotalViewsInTopTags,
    TotalPostUpVotes,
    TotalPostDownVotes,
    TotalBountyEarned,
    coalesce(SampleTopTag, 'NoTopTag') as FavoriteTag,
    coalesce(TopHotQuestionTitle, 'None') as TopHotQuestionTitle,
    coalesce(TopHotQuestionDate::text, 'N/A') as TopHotQuestionDate,
    TopHotQuestionScore
from FinalAggregated
order by Reputation desc, TotalScoreInTopTags desc;