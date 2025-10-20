with recursive TopTags AS (
    select t.Id, t.TagName, t.Count,
        row_number() OVER (ORDER BY t.Count DESC) as rn
    from Tags t
), LegendVotes as (
    select vt.Id, vt.Name from VoteTypes vt where vt.Name IN ('UpMod', 'DownMod', 'Close', 'Reopen', 'BountyStart', 'BountyClose')
), RelevantPosts as (
    select p.*
    from Posts p
    join TopTags tt on ('<' || tt.TagName || '>') = any(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), ','))
)
select *
from RelevantPosts;